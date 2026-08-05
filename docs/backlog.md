Last updated: 2026-08-03

# Neural Lace — Harness Backlog

**Last updated:** 2026-08-03 v74 — REQ-C2 estate drain (gated-pipeline-master-2026-08 Task 21):
23 stale ACTIVE plans dispositioned down to 3 honest ACTIVEs (16 COMPLETED, 4 DEFERRED with a
named resume trigger each, 1 already-DEPRIORITIZED note formalized to DEFERRED — full evidence
in docs/reviews/2026-08-03-estate-drain-record.md); nl-issues untriaged 170->5 via the mechanized
supersession sweep; 738 dead/root-caused monitor alerts bulk-acked (doctor-red + sweep-timeout
classes, both confirmed stopped/tracked-elsewhere); worktree prune EXECUTE list (38 verified-safe
agent-* worktrees) handed to the orchestrator, not run from this worktree-isolated session. Prior
— 2026-07-31 v73 — integration merge (desktop stack + wip/harness-hardening
takeover wave); both prior v72 notes preserved. Desktop v72 — ROADMAP-R11 rows 01-03 (ACTIVE-PATH-EXPANSION,
L0-FOUR-BUCKET-STRIP, KANBAN-MASTER-CHIPS) found ALREADY BUILT on master @18e8f65 (the
orchestrator's gap-closures landed in the SAME commit as the R11 hierarchy-renderer build,
2026-07-27 — the filed rows were never removed after the fix). Verified structurally
(self-test web/cockpit.selftest.js 305/0, incl. R9-2b/R11-L0/R11-C6/R11-I4 assertions) AND
at runtime on a live :7799 instance: real-data four-bucket strip + active-path
auto-expansion observed directly; the kanban master-chip rule was proven via a synthetic
master/child_plans payload (fetch-override injection, since no real in-repo master/child
family currently exists) rendering exactly two child cards each carrying the master's
chip, master itself never its own card. No code changes were needed; rows removed. Prior —
2026-07-18 v71 — cockpit-roadmap-redesign ACTIVE @70f7133: five-round operator
sit-down synthesized, BOTH design gates run (arch SOUND-WITH-AMENDMENTS A1-A10; ux FAIL→delta
PASS-WITH-CONCERNS, C1-C9/I1-I6 + delta R1-R6 all folded); cockpit-ui-polish SUPERSEDED+archived
(absorbed as tasks 6+8); badge-storm auditor fix LANDED+DEPLOYED (unmatched_dispatch age-bounded
to marker-retention horizon; live :7733 verified 718→0 drift chips); task-1 builder (derived
six-value status + roll-up law + complete-oracle port) dispatched; GATE 2/3 probe-log analysis
running; nl-issue triage escalation auto-filed (62 untriaged, row below). Prior — 2026-07-17
v70 — cockpit-v2 BUILD: Task 1 (ONE parser/resolver, plan-parse.js) verified PASS conf 9 + flipped; Task 2 (exporter + derive-lib A4 refactor) landed with the Task-1 seam closed at integration (no third grammar shipped); integrated suites plan-parse 14/14, exporter 11/11, server 148/0, cockpit 84/84. reap-what-you-spawn doctrine caught a live child.kill() Windows leak in Task 2 own self-test (fixed via tree-kill; class flagged for other test files). Prior — 2026-07-17 v69 — ask-rooted-workstreams-p1 CLOSED (18/18, deployed :7733, archived); evidence-bar-enforcement CLOSED (Check 17 BLOCKING+verified; agent-design-gate + agent-commit-gate live OBSERVE-FIRST, flip criteria in manifest — probe-log review pending); merge-scan incremental cursor shipped (36/36, warm 2.5s); server suite 139/0 (first-ever full pass); 5 over-cap doctrine compacts trimmed, Evals CI GREEN again; downstream-product design v2 (Fable) on master w/ operator D1-D4 (D1 folder approved: create-as-proposed); cockpit-v2 v3 in Fable architecture review. 52 nl-issues untriaged (analyst wave queued). Prior — 2026-07-13 v68 — overnight autonomous run: PT-FORK-SYNC-NOT-RUNNING-01 **RESOLVED** (master-drift-autocorrect shipped + live); GAP-51 resolved (dirty-tree reconcile); HARNESS-GAP-45 SCHEDULED (chip session building it); 2 new build-doctrine rows from the tranche-4 supersession audit (FEEDBACK-LOOP-01, ORCHESTRATOR-FATE-01); ~10 new nl-issues filed to the machine ledger (close-plan awk, write-evidence cwd, plan-edit-validator integer-ID, review-finding-fix stale EDITMSG, install skills-wipe, needs-you fixture pollution, et al.). Prior — 2026-07-06 v67 — nl-issue backlog triage (E.8 convert step): 19 untriaged ledger entries dispositioned (8 wontfix-landed incl. F.L functional-link check / E.7 activation guardrails (storm cap, tombstones, liveness guard) / manifest 6-doctrine-file coverage gap / scope-enforcement-gate no-verify message fix / vaporware-volume CI relocation; 1 task-absorbed into observability O.8 estate-coordination protocol; 9 new backlog rows below: CANONICAL-COUNTERS-01, NL-FINDING-037 (purge-selftest-pollution --apply exit-1), PROGRESS-FIELD-01, MANIFEST-NEEDS-YOU-DRIFT-01, E6-HEADER-HARDENING-01, RESUMER-SCHEDULED-EXIT1-01 (reproduced live), SCHEDULED-TASK-HEALTH-01, JQ-WRITER-CLASS-AUDIT-01, WINDOWS-EOL-LF-CHECKLIST-01). Prior — 2026-07-03 v65 — NL-FINDING-029 hooksPath fixture sweep SHIPPED (PR #80, master c1d6dc3): 43 `core.hooksPath ""` overrides across 25 hook self-test fixtures (incl. post-#79 pre-compact-continuity recurrence), all affected suites verified green; findings 029 (the class) + 030 (CRLF-intolerant PR-template validator, discovered landing the PR — new item PR-TEMPLATE-CRLF-01 below) filed; GOLDEN-EVAL-ENV-01 is the eval-surface sibling of the same class, cross-ref added. Prior — 2026-07-03 v64 — doctor --full LITERAL GREEN 8/8 on live mirror @ b8a1597 (first-ever full-sweep green; three defect classes fixed en route — timeouts/budget 1500s, two hard-fail hooks, task-binding retry-guard suite flake NL-FINDING-028; evidence addendum in nl-overhaul evidence file). Prior — 2026-07-03 v63 — D.5-remediation follow-ups: SELFTEST-ORACLE-PIN-01 added (reviewer minor — self-tests should pin canonical repo, not ambient cwd; fold into E.10); findings 022 (heartbeat theater) + 023 (pin-d remediation-command class) filed in the ledger. Prior — 2026-07-03 v62 — **NL Overhaul Wave C COMPLETE** (PRs #68/#69/#70/#71 merged, master 65b7539): context diet LIVE (rules dir 8,293B, was 883,882; doctor GREEN 7/7 with byte-budget + manifest checks), doctrine-jit injection probe-verified, D.1 signal-ledger verified + E.4 synthetic-runner stable subset landed early (3 scenarios + CI wiring deferred to post-D.5). New: GOLDEN-EVAL-ENV-01 (below), NL-FINDING-014 (findings ledger). Wave D next (fresh session; runbook in SCRATCHPAD). Prior — 2026-07-02 v60 — **Plan-estate dispositions executed per DEC-2026-07-02-002**: closed `exact-ask-rule-2026-06-14` (COMPLETED — a resurrected top-level `Status: ACTIVE` duplicate of a plan already archived+closed via `f9c1002`/PR #63; the stale top-level copy was removed, the true archived completion record stands); `triage-stale-plans-2026-06-17` → SUPERSEDED; `housekeeping-staged-harness-batch-2026-06-19` → SUPERSEDED (genuine orphaned subset preserved on `salvage/pre-push-pii-patterns-20260702` @ `0a44e69`); `validation-discipline-agent-encode-2026-06-19`, `orchestrator-prime`, `dispatch-coordination-redesign` → all DEFERRED (re-engage post nl-overhaul F.4). 3 discoveries dispositioned (superseded/decided). Filed **WORKSTREAMS-UI-PURPOSE-AUDIT-01** (P1 — operator verdict the Workstreams UI has failed its purpose; dedicated audit needed, explicitly outside nl-overhaul scope). `wim-deploy-age-guard-fix.md` confirmed already archived (not top-level ACTIVE) — no action needed. Prior — 2026-07-02 v59 — **NL overhaul program backlog reconciliation pass 1** (task B.9 of `docs/plans/nl-overhaul-program-2026-07.md`): marked 10 entries `(absorbed by docs/plans/nl-overhaul-program-2026-07.md — <task>)` — GAP-20/21/22 (→ program governance F.1), P0 synthetic-session-runner (→ E.4), waiver-density alarm/GAP-31 (→ E.3), continuation-enforcer.sh Stop-hook wiring gap (→ D.3, new entry — not previously tracked as a discrete line), GAP-52 (→ B.3), GAP-53 (→ D.4), tool-call-budget `--ack`/HMAC bypass item (→ D.6 retirement), GAP-42 (→ E.4 CI substrate). Closed 2 already-fixed items with evidence: GAP-19 (`session-wrap.sh refresh` confirmed wired in `settings.json.template`'s Stop chain) and HARNESS-HYGIENE-STALE-PLANS-01 (ACTIVE-plan count now 7, down from the 24-of-37 verified 2026-06-01). Prior — 2026-06-12 v58 — **Workstreams status-surface redesign SHIPPED** (`docs/plans/workstreams-ui-status-surface-redesign-2026-06-11.md`, 11/11 tasks task-verifier PASS, 4/4 runtime acceptance scenarios PASS via end-user-advocate runtime mode against an isolated copy of live state): the GUI is now a shared status surface — per-project count cockpit (fixed density), bounded waiting-on-you list, per-project drill tree (color=STATUS/icon=KIND, amber=needs-you only), editable My-tasks + Backlog with promote (reusing `backlog-activated`; only new event = `item-removed`), context-card with the completeness gate (contextless decisions can never render as actionable; all 8 `window.prompt` sites retired), and the emit-discipline contract so future decisions/questions are born context-complete (`workstreams-emit.sh` + rules contract, self-test 66/66). **Filed WS-UI-FOLLOWUPS-01** (4 advocate UX flags + builder edges, below). Prior — v57 — **HARNESS-GAP-49 ABSORBED + FIXED** (`docs/plans/fix-plan-lifecycle-cwd-resolution-2026-06-12.md`): `plan-lifecycle.sh` now derives its repo root from the EDITED FILE's path (`git -C "$(dirname <file>)" rev-parse --show-toplevel`) and runs every archival git operation `git -C <that-root>` — never from the session cwd. Second live instance had occurred 2026-06-11 (cross-REPO this time, not just cross-worktree: a neural-lace-rooted session flipping Status on a sibling product repo's worktree plan deleted it from that repo and staged it into neural-lace). Cross-repo self-test scenario 10 added (10/10 PASS); class catalogued as **FM-032**; `plan-status-archival-sweep.sh` audited same-session and confirmed already file-rooted (no change needed); live mirror synced byte-identical. **Filed HARNESS-GAP-51** (main checkout's foreign staged batch needs operator-supervised reconcile — a stale staged REVERSION of `docs/failure-modes.md` deleting FM-024..FM-031 was found in it and neutralized via restore-from-HEAD this session). Prior — 2026-06-10 v56 — **Pending-discoveries triage (10 master discoveries → 0 still-undecided except 1 deliberately-held greenlight): filed HARNESS-GAP-50** (session-wrap Signal 3 global-4h-window false attribution + missing retry-guard wiring — decided A+C per discovery 2026-05-17, implementation deferred to a dedicated session). Reversible fixes executed in the same triage branch: close-plan.sh `Verification:` parser last-occurrence-wins + S12 regression (discovery 2026-05-11; class-swept into plan-reviewer.sh Check-5 exemptions + collision notice and wire-check-gate.sh); bug-persistence-gate recognizes `docs/prd.md`/`docs/prd/` as durable targets + S6 (discovery 2026-05-16); git-discipline Rule 4 staged-set verification (discovery 2026-05-21); install.sh global hooksPath pinned to the STABLE main checkout, never a prunable worktree (discovery 2026-05-26 item 3). Status flips: 2026-05-15→implemented (interactive-process-fidelity.md), 2026-05-27 checkout-divergence→implemented (unification cutover), 2026-05-27 conv-tree-v4→superseded (Workstreams R-rebuild), 2026-06-02 backfill→implemented (orchestrator-prime forward emission); 2026-05-25 dispatch-coordination stays pending with a current-state note (greenlight is Misha's). Prior — 2026-06-10 v55 — **Stale-plan triage (3 plans): cross-machine coordination plan SUPERSEDED + residue filed (CROSS-MACHINE-COORD-RESIDUE-01); close-plan.sh rename-only-closure-commit defect FIXED (new step 7 pathspec-limited closure commit; S11 regression scenario; self-test 14 checks/11 scenarios 0 fail); filed HARNESS-GAP-49** (plan-lifecycle.sh resolves repo root from the SESSION cwd, so a terminal-status flip on a plan inside a worktree moves+stages the file into the MAIN checkout's index — observed live this triage, polluting another session's staged batch; cleaned up same-session). Triage verdicts: `cross-machine-workstreams-coordination-2026-06-04` → SUPERSEDED by the closed Workstreams consolidation (`workstreams-consolidation-2026-06-08`, Misha-approved single canonical state file) + R-rebuild (the per-host tree-state peer-merge design is dead; coord-push/pull + Phase A/B slices already shipped remain in use); `plan-lifecycle-redesign` → stays ACTIVE with a Decisions Log status entry (design phase done, R1–R8 implementation unstarted and still wanted — 372 live acceptance waivers are the evidence; close-plan fix shipped under its in-flight scope); `orchestrator-prime` → stays ACTIVE by design (Decisions Log entry: it IS the running program; closure = program completion incl. the One Season reminder + completion report per the portfolio tracker). Prior — 2026-06-10 v54 — **Filed HARNESS-GAP-48** (UX/CX review criterion never folded into completion-criteria-gate). The customer-facing-review gate (ADR 053, landed 2026-06-10 from the 2026-06-02 salvage branch) mechanically enforces UX-family + end-user-advocate review on customer-facing spawns at session wrap; the 9th-criterion spec handed off via `.claude/state/spawned-task-results/` during the 2026-06-02 parallel build was never reconciled into the shipped 8-criterion `completion-criteria-gate.sh` (ADR 049). Prior — 2026-06-03 v53 — **Filed HARNESS-GAP-45** (anti-vaporware policy doesn't cover config controls). Misha flagged that the downstream product's permissions matrix had 6/16 decorative toggles — controls that render but don't change behavior — which the anti-vaporware policy should have caught. Proposed: a FUNCTIONALITY-OVER-COMPONENTS clause for config controls + a `functionality-verifier` config-control rubric + a generic registry-vs-callsite invariant + a `vaporware-config-control` failure-mode entry. Originating fix: the downstream product #437 (make every permission toggle effective). No harness code shipped this entry — backlog filing only (the policy/rubric/failure-mode edits are queued). Prior — 2026-06-02 v52 — **Fixed the Workstreams GUI tree flat-list** (`workstreams-ui/web/app.{js,css}`, fix `e98deaf`; plan archived `docs/plans/archive/workstreams-tree-real-nesting-2026-06-02.md`). Browser-verified (puppeteer-core + system Chrome) root cause: the prior fix (`3a8138b`) added per-tier `.tree-item.d1/.d2/.d3` indent CSS, but the live data has `tier=(none)` on all 63 nodes and ZERO Workstream/Sub-task nodes — so every one of the 35 items collapsed to `.d1` (`distinctItemX:[50]`, 11px past the title), a flat dump. A renderer can't show tiers the data doesn't contain. Fix: derive a real intermediate tier from `kind` (Decisions/Questions/Actions) + render true guide-rail nesting via `.tree-kids` containers, so the workstream-less view reads as Project → Kind group → WorkItem with each tier at a distinct, stepped x (measured `proj=10 → group=32 (+22) → item=62 (+30)`); the Workstream/Sub-task tiers still light up automatically when backfill adds real workstream nodes (`renderWorkstream` path preserved). New `regression.e2e.js` **bug#9** (tier-geometry: asserts a real intermediate tier exists AND each tier x is strictly stepped ≥12px — catches "indented but still visually flat", the exact gap the old bug#1 `firstItem.x > title.x + 4` missed) + a **puppeteer-core fallback** so the browser suite runs against system Chrome without the 150MB Chromium download. Verified: regression 10/10, state selftest 19/0, responsive 22/0 (R14 updated to the new structure). Shipped to **PT master `d6e46a1` + personal master `908633e` — trees identical `5cc16b94`**. No new backlog items surfaced (focused fix, complete). Prior — 2026-06-02 v51 — Shipped **`session-start-auto-install.sh`** (ADR 048): a SessionStart hook that continuously, surgically syncs live `~/.claude/hooks/` + `~/.claude/scripts/` from the freshest fetched `origin/master` ref (not the working tree — sidesteps the install footgun), master-wins-with-backup + additive validate-before-swap `settings.json` merge, content-compared modulo CRLF/LF, idempotent, 13-scenario self-test. Closes the cross-machine propagation gap (no per-machine `install.sh`). v2 residual `AUTO-INSTALL-V2` filed below. Prior — 2026-06-02 v50 — **PT↔personal fork reconcile** (this session). Merged the two divergent NL forks to a single union tree: PT's Workstreams Phase 1–4 + Component-B reconciler + hygiene-2 + git-best-practices AND personal's decision-context-gate + pr-health-snapshot-gate + F7 doc-gate + D8/D9/D10 principles-wiring now coexist on both masters (different SHAs, identical tree per the established sync posture). ADR-number collision resolved: decision-context ADR renumbered **045→047** (PT already holds 045-workstreams-reframe + 046-workstreams-lifecycle-emit) — refs swept. Follow-ups filed below: (1) port personal's decision-context fence-field view-rendering (renderItemDetails, ~138 lines) into PT's rewritten four-tier `workstreams-ui/web/app.js`; (2) update `decision-context-gate.sh` + emit recognition for the `conversation-tree-ui`→`workstreams-ui` rename. Prior — 2026-06-01 v49 — **Filed 3 new friction items + augmented 1, from a settings-divergence/install.sh investigation session.** New under "Open work — substantive deferrals": `HARNESS-HYGIENE-STALE-PLANS-01` (24-of-37 top-level plans are chronically `Status: ACTIVE`, count verified this session; `scope-enforcement-gate.sh` cross-blocks unrelated sessions against them — the GAP-29/30/31 plan-staleness family in practice; needs a one-time archival sweep), `GH-AUTH-AUTOSWITCH-WORKORG-01` (the active `gh` identity flips to the work-org account on push, which lacks merge perms on the personal-account remotes, so every `gh pr merge` needs a manual `gh auth switch` — distinct from GAP-12's SSH-multi-push fix, which only covered *pushes*, not the gh-API merge path), `PT-FORK-SYNC-NOT-RUNNING-01` (work-org fork mirrors drift after merges; `sync-pt-to-personal.sh` apparently not firing on schedule / incomplete coverage). The 4th reported item (review-finding-fix-gate stale-`COMMIT_EDITMSG`) was already **HARNESS-GAP-23** — augmented in place with the alias `REVIEW-FINDING-FIX-GATE-COMMIT-EDITMSG-LAG-01` + a cleaner `commit-msg`-hook `argv[1]` fix angle, NOT duplicated. All three new items P2/`priority:medium`. v48 — **Un-redded master's `Hooks self-test` workflow.** Investigation (orchestrator check-in re: "lots of 2026-05-31 PR failures") found the dominant failure was `decision-context-gate.sh --self-test` failing cold in CI (exit 1, not allowlisted) — shipped by PR #45 (decision-context substrate, merged 2026-05-31), which turned master red and propagated to PR #46 (f7-doc-gate). Root cause: the hook's node+zod+`state.js`-facade emit/validation path can't run in CI because `hooks-selftest.yml` never installs `conversation-tree-ui` node deps (same class as the 3 already-allowlisted conv-tree hooks). Remediation shipped: added `decision-context-gate.sh` to `KNOWN_FAILING_HOOKS` with a dated tracking comment (matches established pattern; fully reversible). Filed **HARNESS-GAP-42** for the real class-fix (install conv-tree node deps in the workflow → de-allowlist all four). PR #46's *second* failure (Server-side enforcement) is a stale PR-template miss — body was fixed, check wasn't re-triggered. v47 — Shipped the **git-best-practices 9-item coordinated initiative + item 10**. 7 items shipped (items 4 + 5 already in place at start) plus item 10 (priority-bumped after Office_PC's session asked the operator for VERCEL_TOKEN despite the existing CLAUDE.md "NEVER ask" rule — install.sh now warns when `~/.claude/local/credentials-reference.md` is missing or still the unfilled template stub). Eight item PRs + one closure PR + one item-6 bugfix PR + one item-10 PR landed across PRs #43–#53; each cherry-picked to personal master via the new `sync-pt-to-personal.sh`. Final tree-equivalence between PT and personal master verified at tree `408f8fbe5e6bfd569cb30f7dbac20c8e5d78939a`. Plan archived at `docs/plans/archive/git-bestpractices-9-item-initiative-2026-05-29.md` with full per-item completion report. Notable friction surfaced (for operator discussion, NOT filed as work): `task-completed-evidence-gate.sh` mis-fires on TodoList task IDs (numeric session-task IDs collide with plan-task IDs); item 7's reserved-branch broadcast pushes only to `origin` in v1 (cross-remote PT+personal visibility deferred); no SessionEnd hook in Claude Code today so item 7's cleanup is timestamp-based. v46 — Shipped **drift-check tree-comparison fix** (this PR). The three drift-detection components (`adapters/claude-code/scripts/check-cross-repo-drift.sh`, `adapters/claude-code/sync.sh` post-push verify, `adapters/claude-code/hooks/cross-repo-drift-warn.sh`) compared `.commit.sha` — which under the 2026-05-29 divergent-history-identical-content sync posture (one repo canonical; the other receives the same content via cherry-pick + non-force direct push) would false-positive on every invocation because the two repos intentionally have different commit SHAs forever (each cherry-pick produces a distinct commit object). Caught 2026-05-29 when reviewing post-reconciliation state. Fix: all three components now compare `.commit.commit.tree.sha` (the tree the master tip points at) — content equivalence is the right check. Operator-facing prose throughout swept from "SHA" / "commit SHA" → "tree hash" / "content hash". Self-tests extended: `check-cross-repo-drift.sh` ST6 (same-tree-different-commit → rc 0) + ST7 (different-tree → rc 1) using a mock `gh` on PATH; `sync.sh` T7 (mock-gh tree-hash equivalence → rc 0). Also fixed a pre-existing latent test bug in `check-cross-repo-drift.sh`: the `CONFIG_FILE` env var passed into a subshell invocation of the script was being shadowed by the global default (only `CROSS_REPO_DRIFT_PAIRS` was consulted); now both are honored, so ST5 passes on machines where the real per-machine pairs config exists. Live verification: post-fix, the two repos with identical tree hashes but different commit SHAs report OK / rc 0 — exactly the case the fix handles. v45 — Filed **HARNESS-GAP-39** (cloud-orchestrator hook-detector lint). Surfaced by the conv-tree-auto-current fix (PRs #24/#25, master `02f3ad9` + `dbc1354`): `conversation-tree-emit.sh --on-spawn` is wired in `adapters/claude-code/settings.json.template:244-250` as PreToolUse on `mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task`, but the audit log at `~/.claude/logs/conversation-tree-emit.log` (1463 `--on-spawn` entries since 2026-05-18) shows ALL entries are self-test fixtures — every session ID matches the `sess-st-NN` self-test pattern, every title matches a self-test fixture name (`"Hello mcp__ccd_session__spawn_task"`, `"Idem"`, `"NoSentinels"`, `"WithSentinel"`, `"Tiny"`, `"Branch Six"`); zero production firings across ~5 days. Root cause: the Dispatch orchestrator (`mcp__ccd_session__spawn_task`) runs in the cloud per `automation-modes.md` Mode 3, where only project `.claude/` is loaded — `~/.claude/` hooks never fire. The wiring was theater; we shipped without knowing. Proposed P2 lint: scan the audit log for hooks whose only firings are self-tests (recognizable by `/tmp/` sinks OR `sess-st-NN` session IDs) over a 14-day window and flag the wiring as suspect. Companion to GAP-34 (`end-user-advocate` not dispatchable in Dispatch env — same class). v44 — Shipped the **diagnostic-first protocol + hypothesis-vs-proof labeling + refutation-criteria requirement** rule trio (PR #22 → master `ec46fcf` / `81aca0d`; closure PR #23 → `70b76ab` / `fe1ccc2`). Three Pattern-class rules now load into every Claude session via the harness boot path. (1) `rules/diagnosis.md` new top-section **DIAGNOSTIC-FIRST PROTOCOL** — first tool call on any production-failure investigation MUST be a runtime/error-log pull (`vercel logs` / Sentry / Datadog / Supabase logs / webhook delivery logs / job-runner logs); inferential evidence (probe behavior, code reading, bisects) permitted only after logs are examined or after explicit in-band "logs are inaccessible because X" with a concrete reason. (2) `rules/claims.md` (new file) — every causal claim tagged PROVEN (with cited evidence) or HYPOTHESIZED (with refutation criterion); naked confident phrasing prohibited. (3) Same `rules/claims.md` — before authoring an implementation plan on top of a hypothesis, write the refutation criterion AND look for refuting evidence before committing engineering resources. Operationally reinforced in `agents/plan-phase-builder.md` "Investigation-work mandate" (three clauses for dispatched investigation work). Updated `CLAUDE.md` Detailed Protocols + `vaporware-prevention.md` enforcement map (2 rows) + `harness-architecture.md` rules table (1 new + 1 extended). Filed `FM-029` ("Investigation proceeds from inferential evidence without first capturing runtime/error logs from the affected system") + ADR `035` (with its own Refutation Criterion: operator-CONFIRMED if 5+ future investigations honor the protocols; mechanical enforcement reopened if 1+ violate) + lessons doc `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` (case summary + 6 root causes + harness changes + discriminator distinguishing FM-029 from FM-001 from FM-028). **Originating case:** 8+ days of misdiagnosis on a downstream-product Vercel deployment where a "Lambda 10s INIT cap cold-init deadlock" narrative was built from bisect correlation + code reading + dependency analysis WITHOUT pulling Vercel runtime logs once; the actual error (`You cannot use different slug names for the same dynamic path ('id' !== 'orgId')` — a Next.js dynamic-segment naming conflict) appeared 1760× in 2000 log lines on the broken deployment; a friend running `vercel logs` found it in ~30 seconds; the misdiagnosis fed a multi-day platform-migration plan that would not have helped. Misha course-corrected the orchestrator in chat across multiple sessions; the corrections didn't persist because chat is not the harness's durable rule layer. **Friction-reflexion item surfaced for operator discussion (NOT filed):** `task-completed-evidence-gate.sh` uses bare numeric task-IDs (`1`, `2`, `6`) without a plan-namespace prefix, so session-todo IDs collide with any active plan's numeric task IDs; emitted ~3 several-hundred-line BLOCKED messages during this session searching unrelated active plans (conv-tree-ui-v1.1.2-polish, misha-decision-batch-handoff) for evidence that doesn't apply. Updates still succeeded — hook emitted feedback only, not a hard block at TaskUpdate level — but the friction is noisy. Worth a discuss-first conversation whether the hook should ignore bare-number IDs (since real plan IDs are `1.1`, `A.1`, etc. and only bare-number form collides) or require namespace prefix. v43 — Shipped the AI-natural-prose answer-form fallback in `.github/scripts/validate-pr-template.sh` (PR #21, master `f70e1e6`; closure `e859b5f`). Misha flagged a 4a25348 PR Template Check failure as the second instance of recurring noise; triage pulled 17 recent failures (`gh run list --status failure --limit 30`) and found 13/17 shared a single root cause — AI-spawned PRs write the mechanism answer as a prose paragraph (`**(b) New catalog entry proposed.** ...content...`) instead of using the strict `### a)/### b)/### c)` heading scaffold. The validator was correctly enforcing its declared contract, but the dominant author-class produced a different naturally-occurring form. Fix: added `detect_ai_prose_form` + `validate_rationale_length_prose` + `form_source`-aware branching in `validate_pr_body`. Strict heading detector remains primary; prose form is fallback when heading returns NONE. Prose form requires ≥30 chars of substantive non-placeholder content in the section to register as a selection; (c)-rationale ≥40-char threshold still applies via the sibling whole-section counter. Heading wins when both forms are present in the same body (case 14 of the self-test). Self-test extended from 9 to 15 cases (10/11 PASS prose, 12 FAIL on too-short (c) rationale, 13 FAIL on insufficient substance, 14 heading-precedence, 15 placeholder-embedded-in-prose). **End-to-end CI integration test**: PR #21's own body used AI-prose form; run `26263692560` returned `[pr-template] answer form: b (source: prose)` → `verdict: PASS` — fix works against a real `pr-template-check.yml` invocation, not just local self-tests. Also touched: `.github/PULL_REQUEST_TEMPLATE.md` (note that two writing styles are accepted), `adapters/claude-code/rules/planning.md` Capture-codify section (documents both forms; synced byte-identical to `~/.claude/rules/planning.md`). Plan `docs/plans/archive/pr-template-validator-accept-ai-prose.md` uses `build-harness-infrastructure` work-shape (acceptance-exempt; self-tests are the acceptance artifact); closed with completion report appended. **Recommendation going forward:** the "validator gracefully handles common AI-PR shapes" path was taken (one validator, two accepted forms, uniform across all PRs). The alternative ("update every AI session's PR-creation prompt to produce `### x)` headings") was rejected because it requires touching session context everywhere whereas a validator change covers all cases at one site. **Friction-reflexion item surfaced for operator discussion (NOT filed as work):** when `scope-enforcement-gate.sh` blocks via Bash tool, its stderr ("See stderr for the three structural options") is suppressed in the tool wrapper output; diagnose-before-bypass per `gate-respect.md` was harder because the gate's named remediation options weren't visible. Workaround in this session was to grep active plans manually + reason about which of the three options applied. Worth Misha-discussion whether the gate should print to stdout (visible) instead of, or in addition to, stderr — vs. whether the bash-tool wrapper should propagate stderr more faithfully. v42 — Shipped a new external-monitor alert-surfacer hook (PR #19, master `205a012`): `adapters/claude-code/hooks/external-monitor-alert-surfacer.sh` is a generic SessionStart surfacer that reads alert JSON markers from any configured directory (default `~/.claude/state/external-monitor-alerts/`), surfaces up to 5 newest unacked entries as a system-reminder, ack-by-sibling-`.acked` marker; mirrors `spawned-task-result-surfacer.sh` shape; self-test 6/6 PASS. Paired with an instance-specific HTTP probe (an operator-deployed downstream product) at `tools/` (kept under `is_exempt()` per the instance-tooling boundary), self-test 6/6 PASS, plus runbook + plan auto-archived. Architecture-doc inventory entry added. Surfacer wired ONLY in live `~/.claude/settings.json`, NOT in the kit `settings.json.template` — preserves the instance-tooling vs kit boundary (the hook is generic and reusable; the wiring is per-machine). **Seed probe found 6 real anomalies on first execution** — all `TIMEOUT_OR_NETWORK` against the downstream prod target, matching that product's active 2026-05-18 supabase-js fetch-deadlock incident. System worked on first run. Seed alert left UNACKED so the surfacing path is observable on the next session start. **Next-session actions:** (a) enable scheduling via runbook Option A (MCP `scheduled-tasks` cron `*/30 * * * *`, requires one-time user approval) or Option B (Windows Task Scheduler, fully autonomous); (b) triage the seed alert. The generic surfacer is reusable for future external monitors; only the probe + runbook + plan are necessarily named after the specific product. v41 — Closed the Conversation-Tree GUI loop: shipped the Dispatch-side **reader** `conversation-tree-read.sh` (UserPromptSubmit; PR #6 → master `481de18`, closure PR #8 → `a843fe1`). Reads operator-authored GUI events (`actor=="gui"`, response-allowlist) NEW since a per-session cursor via the frozen A2 `readState` facade, resolves node/item titles from the snapshot, injects them as `hookSpecificOutput.additionalContext` so operator GUI responses reach the next Dispatch turn as if typed in chat; dispatch-actor writes never echoed back; always exit 0; cold-start window-bounded; mtime fast-path. Self-test 37/37 (incl. end-to-end walking skeleton); regression unchanged (emit 17/17, state-gate 18/18, stop-gate 8/8); 7/7 task-verified PASS; plan COMPLETED + auto-archived. **One concrete operational issue discovered + persisted here (bug-persistence):** the post-merge `auto-pre-pull` sync stranded the operator's pre-existing uncommitted edits to `neural-lace/conversation-tree-ui/scripts/launch-gui.ps1` in `stash@{0}: auto-pre-pull-20260518T171142Z` (intact, recoverable) — they collide with the v1.1 GUI session's independent rewrite of that same file on master; surfaced not auto-resolved per git-discipline Rule 2; a future session must reconcile (`git stash show -p stash@{0}` vs `git show origin/master:.../launch-gui.ps1`, then deliberate pop-and-resolve OR `git checkout --` the worktree copy since the stash retains it). **Three friction-reflexion items surfaced for operator discussion in the completion report — NOT filed as backlog work per friction-reflexion.md (discuss-first):** (a) the `<50ms` per-prompt-hook target is unachievable on Windows git-bash (bash startup ~150ms floor); (b) `~/.claude/docs/harness-architecture.md` live mirror badly stale vs repo canonical (HARNESS-GAP-14 resync overdue); (c) `conversation-tree-state-gate.sh` structurally false-fires on orthogonal read-only Agent spawns (NL-FINDING-010 class — per-spawn substantive-waiver tax recurs every session dispatching read-only review agents). v40 — Shipped the Claude-side Conversation-Tree event emitter (`conversation-tree-emit.sh`, PR #3 → master `ce216ad`): PreToolUse-spawn `branch-opened` + Stop `concluded` via the frozen A2 facade; dual-sink (main-checkout GUI file resolved via `git --git-common-dir` so worktree sessions hit the watched file + the conv-tree gates' §5 path); titles the branch with the conv-tree-state-gate's Pin-1 primary candidate so candidate-bearing Dispatch spawns genuinely satisfy the gate (proven live). Operator's future Dispatch conversations now auto-populate the GUI. Self-test 17/17; conv-tree gate regressions 18/18+8/8; task-verifier 5/5 PASS. Filed NL-FINDING-008/009/010 in `docs/findings.md`. **Two deferred follow-ups = real future harness work** (dispositioned-defer findings; pointered here per the findings-ledger ledger-vs-queue convention): (1) NL-FINDING-008 — v2 precise child-DONE correlation via the `Report-back: task-id=` sentinel (v1 concludes on the dispatching session's Stop). (2) NL-FINDING-010 — the pre-existing `conversation-tree-state-gate.sh` blocks bare `Task`/`Agent` sub-agent dispatches carrying no Pin-1 token (no writer can satisfy that); needs a gate-side fix (candidates: gate accepts the `sp-<sha1>` hash node the emitter already writes / read-only `subagent_type` exemption / orchestrator-dispatch always injects a `task-id=` sentinel). Also surfaced, low-priority not acted on: `~/.claude/scripts/state-summary.sh:127` benign `[: integer expression expected` on a `0`/`0` compare (self-recovers). v39 — Harness-friction triage (operator-directed, parallelization-blockers). GAP-2 → HARNESS-GAP-37: `automation-mode-gate.sh` now resolves project config from the parent checkout (git-common-dir) when a worktree branched pre-config can't see it; 5/5 self-test. GAP-3 → HARNESS-GAP-38: `session-wrap.sh` tracked-file freshness signals (backlog/roadmap/discoveries + plans_touched) now read the worktree's own toplevel while SCRATCHPAD keeps reading the parent (ADR 028); 10/10 self-test, S1–S8 no regression, S9b negative-control proves no staleness masking. Both mirrored byte-identical. GAP-1 → HARNESS-GAP-36: a downstream pre-customer project's `prd-v1.1-and-audit-resolution` plan diagnosed genuinely incomplete (0/7, unstarted 3 days) — gate firing correctly; dedicated downstream build session spawned to drive it to COMPLETED. NL-FINDING-003/004/005 filed. v38 — Dispatch-worktree accumulation diagnosed + cleaned. ~47 fully-merged worktrees removed across three repos (~50→~27 in one, ~30→11 in neural-lace, 2→1 in a third); zero salvageable content lost (fully-merged = work already in master). Root cause: the desktop-app Dispatch flow creates a sibling worktree per code task and nothing (runtime or harness) removes it on session end — spawn logic is Anthropic-side, not in our control. Shipped the in-our-control fix: `adapters/claude-code/scripts/worktree-prune.sh` (conservative — only removes fully-merged + clean + idle≥3d + unlocked + non-current; session/build noise filtered; `--self-test` PASS; mirrored to `~/.claude/`; harness-architecture.md row added). Weekly scheduled-task spec written (cron `0 9 * * 1`) but creation needs interactive approval (blocked in unsupervised mode) — surfaced for the operator + OS-task-scheduler fallback documented. Full lifecycle/fix/proposals in `docs/reviews/2026-05-17-dispatch-worktree-accumulation.md`; machine-specific surface list in the gitignored companion. Filed HARNESS-GAP-35. Worktrees with potentially-salvageable uncommitted/unmerged work left in place and surfaced individually for the operator's call. v37 — Conversation Tree Management UI PRD SIGNED OFF by Misha. Built via the Build Doctrine guided-PRD-intake protocol (Stages A-F) run INTERACTIVELY with Misha as the actual respondent each stage, after course-correcting an initial proxy-synthesis attempt (he caught zero interactivity at Phase 4). Landed: docs/prd.md (signed off), docs/decisions/031-conversation-tree-ui-architecture.md r4 (Option 4 struck by Misha; Options 1/2/3 live; architecture pick deferred to an interactive ADR-031 r4 + fresh systems-designer pass), parked docs/plans/conversation-tree-ui.md (decomposed the struck Option 4 - to be re-authored), 3 process discoveries. Renumbered the end-user-advocate-not-dispatchable gap 33->34 (master v36 independently shipped a different GAP-33 = prd-validity-reviewer provenance blind spot; references swept). master new interactive-process-fidelity.md rule supersedes this arc proxy-synthesis discovery. v36 — Shipped new doctrine rule `interactive-process-fidelity.md` (Pattern-class): carry-forward context is briefing, not a substitute for the user's authority touchpoints; the structure/authority asymmetry (scaffolding/formatting/gates = autonomous; user answers/dispositions/approvals = NOT); three-step protocol (recognize → surface-and-wait → halt-don't-synthesize); canonical un-synthesizable touchpoint = Stage A N-R-B invisible-knowledge prompt; explicitly notes `prd-validity-reviewer` PASS certifies substance-shape only, NOT convergence provenance. Synced to live `~/.claude/`, harness-architecture.md row added. Codifies the 2026-05-15 PRD-intake incident (Stages A–F run autonomously from Dispatch carry-forward, OQ-9 self-closed, gate PASSed, caught only when user noticed zero interactivity). Filed HARNESS-GAP-33 (the Mechanism backstop: `prd-validity-reviewer` provenance blind spot — flag artifacts whose only authoring provenance is the AI with no user-authorization markers; design-first, not implemented per user instruction). v35 — Filed HARNESS-GAP-32 (close-plan.sh retroactive friction on legacy plans). Surfaced in the same session that filed GAP-29/30/31: when closing two ACTIVE-but-100%-done plans authored 2026-05-12 (after Tranche B's structured-evidence substrate but using the legacy prose-evidence convention), `close-plan.sh` BLOCKED both with "missing structured `.evidence.json` per task." The work was unambiguously shipped (PRs #179, #180 merged to master with full completion reports appended); the evidence-of-completion lives in prose + git history, not in `<plan-slug>-evidence/<task-id>.evidence.json` artifacts. Manual `Status:` Edit (triggering `plan-lifecycle.sh` PostToolUse auto-archive) was the workable path — the same "manual git ops, visible, several steps, appropriately rare" path the script's own header names. Filed as a sibling concern to GAP-29/30 since the gate's retroactive friction is itself contributing to staleness — it's why the two plans sat ACTIVE long enough to bleed ~20 waivers/day each. v34 — Filed three HARNESS-GAP entries (GAP-29, GAP-30, GAP-31) addressing plan-staleness as a class. Surfaced from a downstream-project audit: 14 ACTIVE plans with 1369 acceptance-waivers across 38 worktrees (200 alone on the project's largest in-flight plan, 96 on a since-closed support-agent plan, 69 on a stalled CI-coverage plan). Three distinct staleness archetypes identified: (A) work-shipped-Status-not-flipped — two plans (`capacity-preset-ui-polish`, `team-rollout-documentation-package`) have 100% of tasks AND DoD items checked but Status is still ACTIVE; (B) plan-filed-no-work — a CI-coverage plan 8 days old, 0 commits, 18 unchecked tasks; (C) silent-waiver-accumulation — operators write per-session waivers when an unrelated ACTIVE plan blocks Stop, but no mechanism reads aggregate waiver counts to surface "this plan got 60+ waivers; close-or-justify." GAP-29 proposes a SessionStart `plan-staleness-surfacer.sh` that reads the three signals (DoD-saturation, days-since-last-commit, cross-worktree waiver count) and emits actionable suggestions. GAP-30 extends `pre-stop-verifier.sh` with an "all-checked-but-ACTIVE" detector that surfaces `/close-plan <slug>` at session end with leverage to act. GAP-31 adds a `waiver-density-alarm.sh` that converts the silent waiver accumulator into a forcing function when any plan crosses a threshold. Companion to GAP-22 (escape-hatch sweep) but complementary — waivers themselves are legitimate; the gap is the missing aggregation. v33 — Reshape: the no-AskUserQuestion rule is now Dispatch-conditional, not blanket. MC widget OK on standalone Claude Code clients (Desktop / IDE / terminal); plain text only under remote-Dispatch clients (where the widget doesn't relay). Detection priority documented (env var `CLAUDE_CODE_DISPATCH=1` target convention, `~/.claude/local/dispatch-mode.json` interim fallback, explicit user signal, default standalone). Touched: CLAUDE.md Autonomy, planning.md "Plan-Time Decisions", discovery-protocol.md "Irreversible-decision PAUSE", new example template at `examples/dispatch-mode.example.json`. Filed HARNESS-GAP-28 for the Dispatch spawner to adopt the env var convention. v32 — Shipped HARNESS-GAP-27 option (a) lightweight migration-allowlist for `scope-enforcement-gate.sh`. When `$GIT_DIR/MERGE_HEAD` exists (merge resolution), `supabase/migrations/*.sql`, `prisma/migrations/**`, and `db/migrations/**` are exempt as system-managed. 4 self-test scenarios added (s13-s16); 16/16 PASS. Option (b) union-of-plans deferred per ADR 030 (trigger criteria documented). Also shipped new doctrine rule `gate-respect.md` (diagnose-before-bypass when any gate blocks; codifies the PR #197 lesson — root-cause diagnosis is the first move, applying the gate's named remediation is the second, bypass-with-explicit-user-authorization is the last). v31 — Filed three HARNESS-GAP entries transferred from a downstream-project findings ledger (FINDING-036/037/038, all P2): GAP-24 (wire propagation engine into PostToolUse to surface real-time events; companion to GAP-19), GAP-25 (profile + optimize slow `git log`-based propagation rules — both exceed 1s wall time, blocks promotion to blocking action), GAP-26 (build ADR cross-reference staleness analyzer for KIT-4 — 45 ADRs × 5 canon artifacts makes manual sweep impractical). All three properly belong in the harness, not in any project-level findings ledger; transfer pattern follows the precedent that harness-shaped issues surfaced in downstream-project work get filed here. v30 — Continued autonomous Build Doctrine push: shipped Tranche 6a (propagation engine framework + 8 starter rules + JSONL audit log at `build-doctrine/telemetry/propagation.jsonl`; 14/14 self-test PASS; 10/10 plan tasks PASS) and **Tranche 5a-integration** (audit-log analyzer at `analyze-propagation-audit-log.sh` with `summary`/`cadence`/`unmatched`/`slow` subcommands — 7/7 self-test PASS; `/harness-review` skill Check 13 KIT-1..KIT-7 sweep; pilot-friction template at `templates/pilot-friction.md`; enforcement-map row + harness-architecture section + 5 narrative-doc citations; 8/8 plan tasks PASS). All closures via `close-plan.sh` with zero `--force`. Build Doctrine roadmap headline status v6 — 7 of 8 tranches DONE. **Pre-pilot infrastructure now complete** — Tranche 4 (canonical pilot) is the only structural wall remaining; pilot consumes a fully-wired substrate (doctrine + templates + propagation engine + audit log + ritual + sweep + analyzer + friction template). 5b/6b/7 gate on pilot evidence; 5c/6c/HARNESS-GAP-11 gate on 2026-08 telemetry. v29 — Autonomous Build Doctrine continuation push: shipped Tranches 2 (template schemas — 7 schemas + 7 examples + README, 10/10 PASS), 3 (template content — 22 universal-floor templates × 2 depths + 4 language naming + branching/commits + API-style architectural default + README, 15/15 PASS), and 6-scaffolding (Python orchestrator package — DAG state machine + state types + Dispatcher protocol + ~32 pytest tests + validation-gap README, 9/9 PASS). All closures via `close-plan.sh` with zero `--force`. Tranche 4 (canonical pilot) is the wall — needs user-side decisions: pilot project identity, readiness assessment, cross-repo access, Python-equipped environment for Tranche 6 scaffolding validation. Handoff doc at `docs/plans/tranche-4-canonical-pilot-handoff.md`. Tranches 5, 7, and Tranche 6 propagation engine all gate on Tranche 4 empirical signal per doctrine. Build Doctrine roadmap headline status v3 — 7 of 8 tranches DONE. v28 — REOPENED 4 plans (Tranche E, parent of Tranche 1.5, Tranche F, HARNESS-GAP-17) per user 2026-05-06: original 2026-05-05 closures used close-plan.sh --force bypassing per-task verification on every task; not actually completed. Status flipped COMPLETED → ACTIVE; plans moved back from `docs/plans/archive/` to `docs/plans/`. Re-closure must be genuine (close-plan.sh's --force flag has since been removed). v27 — Path A in flight: state-summary.sh hybrid shipped (4/4 self-tests PASS, demarcated DERIVED + LLM-SYNTHESIS regions); env-var "override" removed from close-plan.sh entirely (was theater for an LLM agent — "loud is not rare" per user 2026-05-06; 13/13 self-tests PASS); session-wrap.sh wired into Stop chain in prior session. Pending Path A item: start-plan.sh for task-start automation. Added HARNESS-GAP-22 — sweep harness for other --force / --no-verify / OVERRIDE-style escape hatches; remove or convert to friction-the-agent-cannot-satisfy. v26 — Tied off the previous session's loose ends in this brief follow-up session: committed `session-wrap.sh` + ADR 027 v2 (Layer 5: handoff-freshness-as-precondition); flipped 2 stale 2026-05-05 discoveries (codenames → implemented; multi-active-stranding → superseded by Tranche E); archived expired `architecture-simplification-gate-relaxation` policy. Master is now CLEAN (zero ACTIVE plans). Added HARNESS-GAP-19 — wire `session-wrap.sh` into Stop chain (script is built and self-tests 5/5 PASS, just not auto-invoked yet). Earlier v25 — **Tranche 1.5 (architecture simplification) substantively complete** in the prior session. 6 of 7 sub-tranches shipped: A (incentive redesign), B (mechanical evidence substrate), C (work-shape library), D (risk-tiered verification), E (deterministic close-plan procedure — **2.8 sec closure benchmark** vs 65K-token baseline), G (calibration loop bootstrap). Tranche F (failsafe audit) deferred to next session — depends on A-E being battle-tested first. ADR 026 (harness catches up to doctrine) + ADR 027 (autonomous decision-making process) + queued-tranche-1.5.md (14 pre-emptive decisions for async user review) + doctrine extensions N1/N2/N3 (now Anti-Principle 16, Principle 17, Principle 18 in `01-principles.md`) all shipped. Hard freeze on new failsafes in effect. Live acceptance test for close-plan.sh deferred to next session — closing the architecture-simplification plans themselves via the new procedure. Closure-validator (today's GAP-16 ship) tagged-for-retirement; Tranche F's first retirement target. 8 plans currently ACTIVE on master (parent + 6 sub-tranches + HARNESS-GAP-17), all substantively done, all closing via close-plan.sh in next session. v24 — HARNESS-GAP-08 (spawn_task report-back) + HARNESS-GAP-13 (hygiene-scan 4-layer expansion) BOTH IMPLEMENTED + auto-archived this session per Option B. 14 task-verifier PASS commits on `verify/pre-submission-audit-reconcile`. Also reconciled stranded pre-submission-audit-mechanical-enforcement plan; HARNESS-GAP-16 added as next-after pickup (closure-validation gate). v23 — HARNESS-GAP-17 Part A IMPLEMENTED in this session: all 5 user-facing narrative docs (README, harness-strategy, best-practices, quality-strategy, CLAUDE.md) updated to reflect Gen 5/6 + Build Doctrine integration arc; live `~/.claude/CLAUDE.md` synced. Part B (docs-freshness-gate narrative-doc extension) remains deferred per original P2 estimate. Earlier v22 — duplicate-numbering conflict resolved: narrative-docs-stale entry (originally tagged GAP-16 in v21) renumbered to **HARNESS-GAP-17**. GAP-16 is the closure-validation gate per the "Open work" pickup list. Both entries were added 2026-05-05 within 40 minutes; the v21 header tagged the docs-stale one GAP-16 first, then the closure-validation entry duplicated the number 40 min later — closure-validation kept as GAP-16 since the "Open work" section treats it as such. v21 — HARNESS-GAP-16 added — user-facing narrative docs (README, harness-strategy, best-practices, quality-strategy, CLAUDE.md) stale post-integration; docs-freshness-gate has narrative-doc blind spot. Earlier 2026-05-05 v20 — HARNESS-GAP-08 absorbed into `docs/plans/harness-gap-08-spawn-task-report-back.md` (per backlog-plan-atomicity rule). pre-submission-audit-mechanical-enforcement plan reconciled and auto-archived this session (was stranded ACTIVE since 2026-05-03 with all 5 tasks shipped but bookkeeping never run; see commits `588b6db` + `4e8f658` on `verify/pre-submission-audit-reconcile` branch). Earlier 2026-05-05 v19 — backlog header restructured for legibility; full version log moved to bottom of file. Phase 1d-G shipped 2026-05-04 (codename scrub + GAP-14-followups + observed-errors-first stub conversion all IMPLEMENTED). Two stale plans archived: `adversarial-validation-mechanisms.md` SUPERSEDED (mechanisms shipped piecemeal), `acceptance-loop-smoke-test-evidence.md` moved to archive (orphan evidence file). Prior — 2026-07-02 v61 — **Wave B merged to master** (PR #68, `a7b7511`): harness-doctor GREEN 6/6 live, estate at 1 ACTIVE plan, constitution drafted (C.5 cutover pending); Wave C running (chip task_cdf27441 session); personal-mirror master sync deferred to Wave-C completion boundary (gh-account race avoidance). Prior — 2026-07-02 v60 — **Plan-estate dispositions executed per DEC-2026-07-02-002**: closed `exact-ask-rule-2026-06-14` (COMPLETED — a resurrected top-level `Status: ACTIVE` duplicate of a plan already archived+closed via `f9c1002`/PR #63; the stale top-level copy was removed, the true archived completion record stands); `triage-stale-plans-2026-06-17` → SUPERSEDED; `housekeeping-staged-harness-batch-2026-06-19` → SUPERSEDED (genuine orphaned subset preserved on `salvage/pre-push-pii-patterns-20260702` @ `0a44e69`); `validation-discipline-agent-encode-2026-06-19`, `orchestrator-prime`, `dispatch-coordination-redesign` → all DEFERRED (re-engage post nl-overhaul F.4). 3 discoveries dispositioned (superseded/decided). Filed **WORKSTREAMS-UI-PURPOSE-AUDIT-01** (P1 — operator verdict the Workstreams UI has failed its purpose; dedicated audit needed, explicitly outside nl-overhaul scope). `wim-deploy-age-guard-fix.md` confirmed already archived (not top-level ACTIVE) — no action needed. Prior — 2026-07-02 v59 — **NL overhaul program backlog reconciliation pass 1** (task B.9 of `docs/plans/nl-overhaul-program-2026-07.md`): marked 10 entries `(absorbed by docs/plans/nl-overhaul-program-2026-07.md — <task>)` — GAP-20/21/22 (→ program governance F.1), P0 synthetic-session-runner (→ E.4), waiver-density alarm/GAP-31 (→ E.3), continuation-enforcer.sh Stop-hook wiring gap (→ D.3, new entry — not previously tracked as a discrete line), GAP-52 (→ B.3), GAP-53 (→ D.4), tool-call-budget `--ack`/HMAC bypass item (→ D.6 retirement), GAP-42 (→ E.4 CI substrate). Closed 2 already-fixed items with evidence: GAP-19 (`session-wrap.sh refresh` confirmed wired in `settings.json.template`'s Stop chain) and HARNESS-HYGIENE-STALE-PLANS-01 (ACTIVE-plan count now 7, down from the 24-of-37 verified 2026-06-01). Prior — 2026-06-12 v58 — **Workstreams status-surface redesign SHIPPED** (`docs/plans/workstreams-ui-status-surface-redesign-2026-06-11.md`, 11/11 tasks task-verifier PASS, 4/4 runtime acceptance scenarios PASS via end-user-advocate runtime mode against an isolated copy of live state): the GUI is now a shared status surface — per-project count cockpit (fixed density), bounded waiting-on-you list, per-project drill tree (color=STATUS/icon=KIND, amber=needs-you only), editable My-tasks + Backlog with promote (reusing `backlog-activated`; only new event = `item-removed`), context-card with the completeness gate (contextless decisions can never render as actionable; all 8 `window.prompt` sites retired), and the emit-discipline contract so future decisions/questions are born context-complete (`workstreams-emit.sh` + rules contract, self-test 66/66). **Filed WS-UI-FOLLOWUPS-01** (4 advocate UX flags + builder edges, below). Prior — v57 — **HARNESS-GAP-49 ABSORBED + FIXED** (`docs/plans/fix-plan-lifecycle-cwd-resolution-2026-06-12.md`): `plan-lifecycle.sh` now derives its repo root from the EDITED FILE's path (`git -C "$(dirname <file>)" rev-parse --show-toplevel`) and runs every archival git operation `git -C <that-root>` — never from the session cwd. Second live instance had occurred 2026-06-11 (cross-REPO this time, not just cross-worktree: a neural-lace-rooted session flipping Status on a sibling product repo's worktree plan deleted it from that repo and staged it into neural-lace). Cross-repo self-test scenario 10 added (10/10 PASS); class catalogued as **FM-032**; `plan-status-archival-sweep.sh` audited same-session and confirmed already file-rooted (no change needed); live mirror synced byte-identical. **Filed HARNESS-GAP-51** (main checkout's foreign staged batch needs operator-supervised reconcile — a stale staged REVERSION of `docs/failure-modes.md` deleting FM-024..FM-031 was found in it and neutralized via restore-from-HEAD this session). Prior — 2026-06-10 v56 — **Pending-discoveries triage (10 master discoveries → 0 still-undecided except 1 deliberately-held greenlight): filed HARNESS-GAP-50** (session-wrap Signal 3 global-4h-window false attribution + missing retry-guard wiring — decided A+C per discovery 2026-05-17, implementation deferred to a dedicated session). Reversible fixes executed in the same triage branch: close-plan.sh `Verification:` parser last-occurrence-wins + S12 regression (discovery 2026-05-11; class-swept into plan-reviewer.sh Check-5 exemptions + collision notice and wire-check-gate.sh); bug-persistence-gate recognizes `docs/prd.md`/`docs/prd/` as durable targets + S6 (discovery 2026-05-16); git-discipline Rule 4 staged-set verification (discovery 2026-05-21); install.sh global hooksPath pinned to the STABLE main checkout, never a prunable worktree (discovery 2026-05-26 item 3). Status flips: 2026-05-15→implemented (interactive-process-fidelity.md), 2026-05-27 checkout-divergence→implemented (unification cutover), 2026-05-27 conv-tree-v4→superseded (Workstreams R-rebuild), 2026-06-02 backfill→implemented (orchestrator-prime forward emission); 2026-05-25 dispatch-coordination stays pending with a current-state note (greenlight is Misha's). Prior — 2026-06-10 v55 — **Stale-plan triage (3 plans): cross-machine coordination plan SUPERSEDED + residue filed (CROSS-MACHINE-COORD-RESIDUE-01); close-plan.sh rename-only-closure-commit defect FIXED (new step 7 pathspec-limited closure commit; S11 regression scenario; self-test 14 checks/11 scenarios 0 fail); filed HARNESS-GAP-49** (plan-lifecycle.sh resolves repo root from the SESSION cwd, so a terminal-status flip on a plan inside a worktree moves+stages the file into the MAIN checkout's index — observed live this triage, polluting another session's staged batch; cleaned up same-session). Triage verdicts: `cross-machine-workstreams-coordination-2026-06-04` → SUPERSEDED by the closed Workstreams consolidation (`workstreams-consolidation-2026-06-08`, Misha-approved single canonical state file) + R-rebuild (the per-host tree-state peer-merge design is dead; coord-push/pull + Phase A/B slices already shipped remain in use); `plan-lifecycle-redesign` → stays ACTIVE with a Decisions Log status entry (design phase done, R1–R8 implementation unstarted and still wanted — 372 live acceptance waivers are the evidence; close-plan fix shipped under its in-flight scope); `orchestrator-prime` → stays ACTIVE by design (Decisions Log entry: it IS the running program; closure = program completion incl. the One Season reminder + completion report per the portfolio tracker). Prior — 2026-06-10 v54 — **Filed HARNESS-GAP-48** (UX/CX review criterion never folded into completion-criteria-gate). The customer-facing-review gate (ADR 053, landed 2026-06-10 from the 2026-06-02 salvage branch) mechanically enforces UX-family + end-user-advocate review on customer-facing spawns at session wrap; the 9th-criterion spec handed off via `.claude/state/spawned-task-results/` during the 2026-06-02 parallel build was never reconciled into the shipped 8-criterion `completion-criteria-gate.sh` (ADR 049). Prior — 2026-06-03 v53 — **Filed HARNESS-GAP-45** (anti-vaporware policy doesn't cover config controls). Misha flagged that the downstream product's permissions matrix had 6/16 decorative toggles — controls that render but don't change behavior — which the anti-vaporware policy should have caught. Proposed: a FUNCTIONALITY-OVER-COMPONENTS clause for config controls + a `functionality-verifier` config-control rubric + a generic registry-vs-callsite invariant + a `vaporware-config-control` failure-mode entry. Originating fix: the downstream product #437 (make every permission toggle effective). No harness code shipped this entry — backlog filing only (the policy/rubric/failure-mode edits are queued). Prior — 2026-06-02 v52 — **Fixed the Workstreams GUI tree flat-list** (`workstreams-ui/web/app.{js,css}`, fix `e98deaf`; plan archived `docs/plans/archive/workstreams-tree-real-nesting-2026-06-02.md`). Browser-verified (puppeteer-core + system Chrome) root cause: the prior fix (`3a8138b`) added per-tier `.tree-item.d1/.d2/.d3` indent CSS, but the live data has `tier=(none)` on all 63 nodes and ZERO Workstream/Sub-task nodes — so every one of the 35 items collapsed to `.d1` (`distinctItemX:[50]`, 11px past the title), a flat dump. A renderer can't show tiers the data doesn't contain. Fix: derive a real intermediate tier from `kind` (Decisions/Questions/Actions) + render true guide-rail nesting via `.tree-kids` containers, so the workstream-less view reads as Project → Kind group → WorkItem with each tier at a distinct, stepped x (measured `proj=10 → group=32 (+22) → item=62 (+30)`); the Workstream/Sub-task tiers still light up automatically when backfill adds real workstream nodes (`renderWorkstream` path preserved). New `regression.e2e.js` **bug#9** (tier-geometry: asserts a real intermediate tier exists AND each tier x is strictly stepped ≥12px — catches "indented but still visually flat", the exact gap the old bug#1 `firstItem.x > title.x + 4` missed) + a **puppeteer-core fallback** so the browser suite runs against system Chrome without the 150MB Chromium download. Verified: regression 10/10, state selftest 19/0, responsive 22/0 (R14 updated to the new structure). Shipped to **PT master `d6e46a1` + personal master `908633e` — trees identical `5cc16b94`**. No new backlog items surfaced (focused fix, complete). Prior — 2026-06-02 v51 — Shipped **`session-start-auto-install.sh`** (ADR 048): a SessionStart hook that continuously, surgically syncs live `~/.claude/hooks/` + `~/.claude/scripts/` from the freshest fetched `origin/master` ref (not the working tree — sidesteps the install footgun), master-wins-with-backup + additive validate-before-swap `settings.json` merge, content-compared modulo CRLF/LF, idempotent, 13-scenario self-test. Closes the cross-machine propagation gap (no per-machine `install.sh`). v2 residual `AUTO-INSTALL-V2` filed below. Prior — 2026-06-02 v50 — **PT↔personal fork reconcile** (this session). Merged the two divergent NL forks to a single union tree: PT's Workstreams Phase 1–4 + Component-B reconciler + hygiene-2 + git-best-practices AND personal's decision-context-gate + pr-health-snapshot-gate + F7 doc-gate + D8/D9/D10 principles-wiring now coexist on both masters (different SHAs, identical tree per the established sync posture). ADR-number collision resolved: decision-context ADR renumbered **045→047** (PT already holds 045-workstreams-reframe + 046-workstreams-lifecycle-emit) — refs swept. Follow-ups filed below: (1) port personal's decision-context fence-field view-rendering (renderItemDetails, ~138 lines) into PT's rewritten four-tier `workstreams-ui/web/app.js`; (2) update `decision-context-gate.sh` + emit recognition for the `conversation-tree-ui`→`workstreams-ui` rename. Prior — 2026-06-01 v49 — **Filed 3 new friction items + augmented 1, from a settings-divergence/install.sh investigation session.** New under "Open work — substantive deferrals": `HARNESS-HYGIENE-STALE-PLANS-01` (24-of-37 top-level plans are chronically `Status: ACTIVE`, count verified this session; `scope-enforcement-gate.sh` cross-blocks unrelated sessions against them — the GAP-29/30/31 plan-staleness family in practice; needs a one-time archival sweep), `GH-AUTH-AUTOSWITCH-WORKORG-01` (the active `gh` identity flips to the work-org account on push, which lacks merge perms on the personal-account remotes, so every `gh pr merge` needs a manual `gh auth switch` — distinct from GAP-12's SSH-multi-push fix, which only covered *pushes*, not the gh-API merge path), `PT-FORK-SYNC-NOT-RUNNING-01` (work-org fork mirrors drift after merges; `sync-pt-to-personal.sh` apparently not firing on schedule / incomplete coverage). The 4th reported item (review-finding-fix-gate stale-`COMMIT_EDITMSG`) was already **HARNESS-GAP-23** — augmented in place with the alias `REVIEW-FINDING-FIX-GATE-COMMIT-EDITMSG-LAG-01` + a cleaner `commit-msg`-hook `argv[1]` fix angle, NOT duplicated. All three new items P2/`priority:medium`. v48 — **Un-redded master's `Hooks self-test` workflow.** Investigation (orchestrator check-in re: "lots of 2026-05-31 PR failures") found the dominant failure was `decision-context-gate.sh --self-test` failing cold in CI (exit 1, not allowlisted) — shipped by PR #45 (decision-context substrate, merged 2026-05-31), which turned master red and propagated to PR #46 (f7-doc-gate). Root cause: the hook's node+zod+`state.js`-facade emit/validation path can't run in CI because `hooks-selftest.yml` never installs `conversation-tree-ui` node deps (same class as the 3 already-allowlisted conv-tree hooks). Remediation shipped: added `decision-context-gate.sh` to `KNOWN_FAILING_HOOKS` with a dated tracking comment (matches established pattern; fully reversible). Filed **HARNESS-GAP-42** for the real class-fix (install conv-tree node deps in the workflow → de-allowlist all four). PR #46's *second* failure (Server-side enforcement) is a stale PR-template miss — body was fixed, check wasn't re-triggered. v47 — Shipped the **git-best-practices 9-item coordinated initiative + item 10**. 7 items shipped (items 4 + 5 already in place at start) plus item 10 (priority-bumped after Office_PC's session asked the operator for VERCEL_TOKEN despite the existing CLAUDE.md "NEVER ask" rule — install.sh now warns when `~/.claude/local/credentials-reference.md` is missing or still the unfilled template stub). Eight item PRs + one closure PR + one item-6 bugfix PR + one item-10 PR landed across PRs #43–#53; each cherry-picked to personal master via the new `sync-pt-to-personal.sh`. Final tree-equivalence between PT and personal master verified at tree `408f8fbe5e6bfd569cb30f7dbac20c8e5d78939a`. Plan archived at `docs/plans/archive/git-bestpractices-9-item-initiative-2026-05-29.md` with full per-item completion report. Notable friction surfaced (for operator discussion, NOT filed as work): `task-completed-evidence-gate.sh` mis-fires on TodoList task IDs (numeric session-task IDs collide with plan-task IDs); item 7's reserved-branch broadcast pushes only to `origin` in v1 (cross-remote PT+personal visibility deferred); no SessionEnd hook in Claude Code today so item 7's cleanup is timestamp-based. v46 — Shipped **drift-check tree-comparison fix** (this PR). The three drift-detection components (`adapters/claude-code/scripts/check-cross-repo-drift.sh`, `adapters/claude-code/sync.sh` post-push verify, `adapters/claude-code/hooks/cross-repo-drift-warn.sh`) compared `.commit.sha` — which under the 2026-05-29 divergent-history-identical-content sync posture (one repo canonical; the other receives the same content via cherry-pick + non-force direct push) would false-positive on every invocation because the two repos intentionally have different commit SHAs forever (each cherry-pick produces a distinct commit object). Caught 2026-05-29 when reviewing post-reconciliation state. Fix: all three components now compare `.commit.commit.tree.sha` (the tree the master tip points at) — content equivalence is the right check. Operator-facing prose throughout swept from "SHA" / "commit SHA" → "tree hash" / "content hash". Self-tests extended: `check-cross-repo-drift.sh` ST6 (same-tree-different-commit → rc 0) + ST7 (different-tree → rc 1) using a mock `gh` on PATH; `sync.sh` T7 (mock-gh tree-hash equivalence → rc 0). Also fixed a pre-existing latent test bug in `check-cross-repo-drift.sh`: the `CONFIG_FILE` env var passed into a subshell invocation of the script was being shadowed by the global default (only `CROSS_REPO_DRIFT_PAIRS` was consulted); now both are honored, so ST5 passes on machines where the real per-machine pairs config exists. Live verification: post-fix, the two repos with identical tree hashes but different commit SHAs report OK / rc 0 — exactly the case the fix handles. v45 — Filed **HARNESS-GAP-39** (cloud-orchestrator hook-detector lint). Surfaced by the conv-tree-auto-current fix (PRs #24/#25, master `02f3ad9` + `dbc1354`): `conversation-tree-emit.sh --on-spawn` is wired in `adapters/claude-code/settings.json.template:244-250` as PreToolUse on `mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task`, but the audit log at `~/.claude/logs/conversation-tree-emit.log` (1463 `--on-spawn` entries since 2026-05-18) shows ALL entries are self-test fixtures — every session ID matches the `sess-st-NN` self-test pattern, every title matches a self-test fixture name (`"Hello mcp__ccd_session__spawn_task"`, `"Idem"`, `"NoSentinels"`, `"WithSentinel"`, `"Tiny"`, `"Branch Six"`); zero production firings across ~5 days. Root cause: the Dispatch orchestrator (`mcp__ccd_session__spawn_task`) runs in the cloud per `automation-modes.md` Mode 3, where only project `.claude/` is loaded — `~/.claude/` hooks never fire. The wiring was theater; we shipped without knowing. Proposed P2 lint: scan the audit log for hooks whose only firings are self-tests (recognizable by `/tmp/` sinks OR `sess-st-NN` session IDs) over a 14-day window and flag the wiring as suspect. Companion to GAP-34 (`end-user-advocate` not dispatchable in Dispatch env — same class). v44 — Shipped the **diagnostic-first protocol + hypothesis-vs-proof labeling + refutation-criteria requirement** rule trio (PR #22 → master `ec46fcf` / `81aca0d`; closure PR #23 → `70b76ab` / `fe1ccc2`). Three Pattern-class rules now load into every Claude session via the harness boot path. (1) `rules/diagnosis.md` new top-section **DIAGNOSTIC-FIRST PROTOCOL** — first tool call on any production-failure investigation MUST be a runtime/error-log pull (`vercel logs` / Sentry / Datadog / Supabase logs / webhook delivery logs / job-runner logs); inferential evidence (probe behavior, code reading, bisects) permitted only after logs are examined or after explicit in-band "logs are inaccessible because X" with a concrete reason. (2) `rules/claims.md` (new file) — every causal claim tagged PROVEN (with cited evidence) or HYPOTHESIZED (with refutation criterion); naked confident phrasing prohibited. (3) Same `rules/claims.md` — before authoring an implementation plan on top of a hypothesis, write the refutation criterion AND look for refuting evidence before committing engineering resources. Operationally reinforced in `agents/plan-phase-builder.md` "Investigation-work mandate" (three clauses for dispatched investigation work). Updated `CLAUDE.md` Detailed Protocols + `vaporware-prevention.md` enforcement map (2 rows) + `harness-architecture.md` rules table (1 new + 1 extended). Filed `FM-029` ("Investigation proceeds from inferential evidence without first capturing runtime/error logs from the affected system") + ADR `035` (with its own Refutation Criterion: operator-CONFIRMED if 5+ future investigations honor the protocols; mechanical enforcement reopened if 1+ violate) + lessons doc `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` (case summary + 6 root causes + harness changes + discriminator distinguishing FM-029 from FM-001 from FM-028). **Originating case:** 8+ days of misdiagnosis on a downstream-product Vercel deployment where a "Lambda 10s INIT cap cold-init deadlock" narrative was built from bisect correlation + code reading + dependency analysis WITHOUT pulling Vercel runtime logs once; the actual error (`You cannot use different slug names for the same dynamic path ('id' !== 'orgId')` — a Next.js dynamic-segment naming conflict) appeared 1760× in 2000 log lines on the broken deployment; a friend running `vercel logs` found it in ~30 seconds; the misdiagnosis fed a multi-day platform-migration plan that would not have helped. Misha course-corrected the orchestrator in chat across multiple sessions; the corrections didn't persist because chat is not the harness's durable rule layer. **Friction-reflexion item surfaced for operator discussion (NOT filed):** `task-completed-evidence-gate.sh` uses bare numeric task-IDs (`1`, `2`, `6`) without a plan-namespace prefix, so session-todo IDs collide with any active plan's numeric task IDs; emitted ~3 several-hundred-line BLOCKED messages during this session searching unrelated active plans (conv-tree-ui-v1.1.2-polish, misha-decision-batch-handoff) for evidence that doesn't apply. Updates still succeeded — hook emitted feedback only, not a hard block at TaskUpdate level — but the friction is noisy. Worth a discuss-first conversation whether the hook should ignore bare-number IDs (since real plan IDs are `1.1`, `A.1`, etc. and only bare-number form collides) or require namespace prefix. v43 — Shipped the AI-natural-prose answer-form fallback in `.github/scripts/validate-pr-template.sh` (PR #21, master `f70e1e6`; closure `e859b5f`). Misha flagged a 4a25348 PR Template Check failure as the second instance of recurring noise; triage pulled 17 recent failures (`gh run list --status failure --limit 30`) and found 13/17 shared a single root cause — AI-spawned PRs write the mechanism answer as a prose paragraph (`**(b) New catalog entry proposed.** ...content...`) instead of using the strict `### a)/### b)/### c)` heading scaffold. The validator was correctly enforcing its declared contract, but the dominant author-class produced a different naturally-occurring form. Fix: added `detect_ai_prose_form` + `validate_rationale_length_prose` + `form_source`-aware branching in `validate_pr_body`. Strict heading detector remains primary; prose form is fallback when heading returns NONE. Prose form requires ≥30 chars of substantive non-placeholder content in the section to register as a selection; (c)-rationale ≥40-char threshold still applies via the sibling whole-section counter. Heading wins when both forms are present in the same body (case 14 of the self-test). Self-test extended from 9 to 15 cases (10/11 PASS prose, 12 FAIL on too-short (c) rationale, 13 FAIL on insufficient substance, 14 heading-precedence, 15 placeholder-embedded-in-prose). **End-to-end CI integration test**: PR #21's own body used AI-prose form; run `26263692560` returned `[pr-template] answer form: b (source: prose)` → `verdict: PASS` — fix works against a real `pr-template-check.yml` invocation, not just local self-tests. Also touched: `.github/PULL_REQUEST_TEMPLATE.md` (note that two writing styles are accepted), `adapters/claude-code/rules/planning.md` Capture-codify section (documents both forms; synced byte-identical to `~/.claude/rules/planning.md`). Plan `docs/plans/archive/pr-template-validator-accept-ai-prose.md` uses `build-harness-infrastructure` work-shape (acceptance-exempt; self-tests are the acceptance artifact); closed with completion report appended. **Recommendation going forward:** the "validator gracefully handles common AI-PR shapes" path was taken (one validator, two accepted forms, uniform across all PRs). The alternative ("update every AI session's PR-creation prompt to produce `### x)` headings") was rejected because it requires touching session context everywhere whereas a validator change covers all cases at one site. **Friction-reflexion item surfaced for operator discussion (NOT filed as work):** when `scope-enforcement-gate.sh` blocks via Bash tool, its stderr ("See stderr for the three structural options") is suppressed in the tool wrapper output; diagnose-before-bypass per `gate-respect.md` was harder because the gate's named remediation options weren't visible. Workaround in this session was to grep active plans manually + reason about which of the three options applied. Worth Misha-discussion whether the gate should print to stdout (visible) instead of, or in addition to, stderr — vs. whether the bash-tool wrapper should propagate stderr more faithfully. v42 — Shipped a new external-monitor alert-surfacer hook (PR #19, master `205a012`): `adapters/claude-code/hooks/external-monitor-alert-surfacer.sh` is a generic SessionStart surfacer that reads alert JSON markers from any configured directory (default `~/.claude/state/external-monitor-alerts/`), surfaces up to 5 newest unacked entries as a system-reminder, ack-by-sibling-`.acked` marker; mirrors `spawned-task-result-surfacer.sh` shape; self-test 6/6 PASS. Paired with an instance-specific HTTP probe (an operator-deployed downstream product) at `tools/` (kept under `is_exempt()` per the instance-tooling boundary), self-test 6/6 PASS, plus runbook + plan auto-archived. Architecture-doc inventory entry added. Surfacer wired ONLY in live `~/.claude/settings.json`, NOT in the kit `settings.json.template` — preserves the instance-tooling vs kit boundary (the hook is generic and reusable; the wiring is per-machine). **Seed probe found 6 real anomalies on first execution** — all `TIMEOUT_OR_NETWORK` against the downstream prod target, matching that product's active 2026-05-18 supabase-js fetch-deadlock incident. System worked on first run. Seed alert left UNACKED so the surfacing path is observable on the next session start. **Next-session actions:** (a) enable scheduling via runbook Option A (MCP `scheduled-tasks` cron `*/30 * * * *`, requires one-time user approval) or Option B (Windows Task Scheduler, fully autonomous); (b) triage the seed alert. The generic surfacer is reusable for future external monitors; only the probe + runbook + plan are necessarily named after the specific product. v41 — Closed the Conversation-Tree GUI loop: shipped the Dispatch-side **reader** `conversation-tree-read.sh` (UserPromptSubmit; PR #6 → master `481de18`, closure PR #8 → `a843fe1`). Reads operator-authored GUI events (`actor=="gui"`, response-allowlist) NEW since a per-session cursor via the frozen A2 `readState` facade, resolves node/item titles from the snapshot, injects them as `hookSpecificOutput.additionalContext` so operator GUI responses reach the next Dispatch turn as if typed in chat; dispatch-actor writes never echoed back; always exit 0; cold-start window-bounded; mtime fast-path. Self-test 37/37 (incl. end-to-end walking skeleton); regression unchanged (emit 17/17, state-gate 18/18, stop-gate 8/8); 7/7 task-verified PASS; plan COMPLETED + auto-archived. **One concrete operational issue discovered + persisted here (bug-persistence):** the post-merge `auto-pre-pull` sync stranded the operator's pre-existing uncommitted edits to `neural-lace/conversation-tree-ui/scripts/launch-gui.ps1` in `stash@{0}: auto-pre-pull-20260518T171142Z` (intact, recoverable) — they collide with the v1.1 GUI session's independent rewrite of that same file on master; surfaced not auto-resolved per git-discipline Rule 2; a future session must reconcile (`git stash show -p stash@{0}` vs `git show origin/master:.../launch-gui.ps1`, then deliberate pop-and-resolve OR `git checkout --` the worktree copy since the stash retains it). **Three friction-reflexion items surfaced for operator discussion in the completion report — NOT filed as backlog work per friction-reflexion.md (discuss-first):** (a) the `<50ms` per-prompt-hook target is unachievable on Windows git-bash (bash startup ~150ms floor); (b) `~/.claude/docs/harness-architecture.md` live mirror badly stale vs repo canonical (HARNESS-GAP-14 resync overdue); (c) `conversation-tree-state-gate.sh` structurally false-fires on orthogonal read-only Agent spawns (NL-FINDING-010 class — per-spawn substantive-waiver tax recurs every session dispatching read-only review agents). v40 — Shipped the Claude-side Conversation-Tree event emitter (`conversation-tree-emit.sh`, PR #3 → master `ce216ad`): PreToolUse-spawn `branch-opened` + Stop `concluded` via the frozen A2 facade; dual-sink (main-checkout GUI file resolved via `git --git-common-dir` so worktree sessions hit the watched file + the conv-tree gates' §5 path); titles the branch with the conv-tree-state-gate's Pin-1 primary candidate so candidate-bearing Dispatch spawns genuinely satisfy the gate (proven live). Operator's future Dispatch conversations now auto-populate the GUI. Self-test 17/17; conv-tree gate regressions 18/18+8/8; task-verifier 5/5 PASS. Filed NL-FINDING-008/009/010 in `docs/findings.md`. **Two deferred follow-ups = real future harness work** (dispositioned-defer findings; pointered here per the findings-ledger ledger-vs-queue convention): (1) NL-FINDING-008 — v2 precise child-DONE correlation via the `Report-back: task-id=` sentinel (v1 concludes on the dispatching session's Stop). (2) NL-FINDING-010 — the pre-existing `conversation-tree-state-gate.sh` blocks bare `Task`/`Agent` sub-agent dispatches carrying no Pin-1 token (no writer can satisfy that); needs a gate-side fix (candidates: gate accepts the `sp-<sha1>` hash node the emitter already writes / read-only `subagent_type` exemption / orchestrator-dispatch always injects a `task-id=` sentinel). Also surfaced, low-priority not acted on: `~/.claude/scripts/state-summary.sh:127` benign `[: integer expression expected` on a `0`/`0` compare (self-recovers). v39 — Harness-friction triage (operator-directed, parallelization-blockers). GAP-2 → HARNESS-GAP-37: `automation-mode-gate.sh` now resolves project config from the parent checkout (git-common-dir) when a worktree branched pre-config can't see it; 5/5 self-test. GAP-3 → HARNESS-GAP-38: `session-wrap.sh` tracked-file freshness signals (backlog/roadmap/discoveries + plans_touched) now read the worktree's own toplevel while SCRATCHPAD keeps reading the parent (ADR 028); 10/10 self-test, S1–S8 no regression, S9b negative-control proves no staleness masking. Both mirrored byte-identical. GAP-1 → HARNESS-GAP-36: a downstream pre-customer project's `prd-v1.1-and-audit-resolution` plan diagnosed genuinely incomplete (0/7, unstarted 3 days) — gate firing correctly; dedicated downstream build session spawned to drive it to COMPLETED. NL-FINDING-003/004/005 filed. v38 — Dispatch-worktree accumulation diagnosed + cleaned. ~47 fully-merged worktrees removed across three repos (~50→~27 in one, ~30→11 in neural-lace, 2→1 in a third); zero salvageable content lost (fully-merged = work already in master). Root cause: the desktop-app Dispatch flow creates a sibling worktree per code task and nothing (runtime or harness) removes it on session end — spawn logic is Anthropic-side, not in our control. Shipped the in-our-control fix: `adapters/claude-code/scripts/worktree-prune.sh` (conservative — only removes fully-merged + clean + idle≥3d + unlocked + non-current; session/build noise filtered; `--self-test` PASS; mirrored to `~/.claude/`; harness-architecture.md row added). Weekly scheduled-task spec written (cron `0 9 * * 1`) but creation needs interactive approval (blocked in unsupervised mode) — surfaced for the operator + OS-task-scheduler fallback documented. Full lifecycle/fix/proposals in `docs/reviews/2026-05-17-dispatch-worktree-accumulation.md`; machine-specific surface list in the gitignored companion. Filed HARNESS-GAP-35. Worktrees with potentially-salvageable uncommitted/unmerged work left in place and surfaced individually for the operator's call. v37 — Conversation Tree Management UI PRD SIGNED OFF by Misha. Built via the Build Doctrine guided-PRD-intake protocol (Stages A-F) run INTERACTIVELY with Misha as the actual respondent each stage, after course-correcting an initial proxy-synthesis attempt (he caught zero interactivity at Phase 4). Landed: docs/prd.md (signed off), docs/decisions/031-conversation-tree-ui-architecture.md r4 (Option 4 struck by Misha; Options 1/2/3 live; architecture pick deferred to an interactive ADR-031 r4 + fresh systems-designer pass), parked docs/plans/conversation-tree-ui.md (decomposed the struck Option 4 - to be re-authored), 3 process discoveries. Renumbered the end-user-advocate-not-dispatchable gap 33->34 (master v36 independently shipped a different GAP-33 = prd-validity-reviewer provenance blind spot; references swept). master new interactive-process-fidelity.md rule supersedes this arc proxy-synthesis discovery. v36 — Shipped new doctrine rule `interactive-process-fidelity.md` (Pattern-class): carry-forward context is briefing, not a substitute for the user's authority touchpoints; the structure/authority asymmetry (scaffolding/formatting/gates = autonomous; user answers/dispositions/approvals = NOT); three-step protocol (recognize → surface-and-wait → halt-don't-synthesize); canonical un-synthesizable touchpoint = Stage A N-R-B invisible-knowledge prompt; explicitly notes `prd-validity-reviewer` PASS certifies substance-shape only, NOT convergence provenance. Synced to live `~/.claude/`, harness-architecture.md row added. Codifies the 2026-05-15 PRD-intake incident (Stages A–F run autonomously from Dispatch carry-forward, OQ-9 self-closed, gate PASSed, caught only when user noticed zero interactivity). Filed HARNESS-GAP-33 (the Mechanism backstop: `prd-validity-reviewer` provenance blind spot — flag artifacts whose only authoring provenance is the AI with no user-authorization markers; design-first, not implemented per user instruction). v35 — Filed HARNESS-GAP-32 (close-plan.sh retroactive friction on legacy plans). Surfaced in the same session that filed GAP-29/30/31: when closing two ACTIVE-but-100%-done plans authored 2026-05-12 (after Tranche B's structured-evidence substrate but using the legacy prose-evidence convention), `close-plan.sh` BLOCKED both with "missing structured `.evidence.json` per task." The work was unambiguously shipped (PRs #179, #180 merged to master with full completion reports appended); the evidence-of-completion lives in prose + git history, not in `<plan-slug>-evidence/<task-id>.evidence.json` artifacts. Manual `Status:` Edit (triggering `plan-lifecycle.sh` PostToolUse auto-archive) was the workable path — the same "manual git ops, visible, several steps, appropriately rare" path the script's own header names. Filed as a sibling concern to GAP-29/30 since the gate's retroactive friction is itself contributing to staleness — it's why the two plans sat ACTIVE long enough to bleed ~20 waivers/day each. v34 — Filed three HARNESS-GAP entries (GAP-29, GAP-30, GAP-31) addressing plan-staleness as a class. Surfaced from a downstream-project audit: 14 ACTIVE plans with 1369 acceptance-waivers across 38 worktrees (200 alone on the project's largest in-flight plan, 96 on a since-closed support-agent plan, 69 on a stalled CI-coverage plan). Three distinct staleness archetypes identified: (A) work-shipped-Status-not-flipped — two plans (`capacity-preset-ui-polish`, `team-rollout-documentation-package`) have 100% of tasks AND DoD items checked but Status is still ACTIVE; (B) plan-filed-no-work — a CI-coverage plan 8 days old, 0 commits, 18 unchecked tasks; (C) silent-waiver-accumulation — operators write per-session waivers when an unrelated ACTIVE plan blocks Stop, but no mechanism reads aggregate waiver counts to surface "this plan got 60+ waivers; close-or-justify." GAP-29 proposes a SessionStart `plan-staleness-surfacer.sh` that reads the three signals (DoD-saturation, days-since-last-commit, cross-worktree waiver count) and emits actionable suggestions. GAP-30 extends `pre-stop-verifier.sh` with an "all-checked-but-ACTIVE" detector that surfaces `/close-plan <slug>` at session end with leverage to act. GAP-31 adds a `waiver-density-alarm.sh` that converts the silent waiver accumulator into a forcing function when any plan crosses a threshold. Companion to GAP-22 (escape-hatch sweep) but complementary — waivers themselves are legitimate; the gap is the missing aggregation. v33 — Reshape: the no-AskUserQuestion rule is now Dispatch-conditional, not blanket. MC widget OK on standalone Claude Code clients (Desktop / IDE / terminal); plain text only under remote-Dispatch clients (where the widget doesn't relay). Detection priority documented (env var `CLAUDE_CODE_DISPATCH=1` target convention, `~/.claude/local/dispatch-mode.json` interim fallback, explicit user signal, default standalone). Touched: CLAUDE.md Autonomy, planning.md "Plan-Time Decisions", discovery-protocol.md "Irreversible-decision PAUSE", new example template at `examples/dispatch-mode.example.json`. Filed HARNESS-GAP-28 for the Dispatch spawner to adopt the env var convention. v32 — Shipped HARNESS-GAP-27 option (a) lightweight migration-allowlist for `scope-enforcement-gate.sh`. When `$GIT_DIR/MERGE_HEAD` exists (merge resolution), `supabase/migrations/*.sql`, `prisma/migrations/**`, and `db/migrations/**` are exempt as system-managed. 4 self-test scenarios added (s13-s16); 16/16 PASS. Option (b) union-of-plans deferred per ADR 030 (trigger criteria documented). Also shipped new doctrine rule `gate-respect.md` (diagnose-before-bypass when any gate blocks; codifies the PR #197 lesson — root-cause diagnosis is the first move, applying the gate's named remediation is the second, bypass-with-explicit-user-authorization is the last). v31 — Filed three HARNESS-GAP entries transferred from a downstream-project findings ledger (FINDING-036/037/038, all P2): GAP-24 (wire propagation engine into PostToolUse to surface real-time events; companion to GAP-19), GAP-25 (profile + optimize slow `git log`-based propagation rules — both exceed 1s wall time, blocks promotion to blocking action), GAP-26 (build ADR cross-reference staleness analyzer for KIT-4 — 45 ADRs × 5 canon artifacts makes manual sweep impractical). All three properly belong in the harness, not in any project-level findings ledger; transfer pattern follows the precedent that harness-shaped issues surfaced in downstream-project work get filed here. v30 — Continued autonomous Build Doctrine push: shipped Tranche 6a (propagation engine framework + 8 starter rules + JSONL audit log at `build-doctrine/telemetry/propagation.jsonl`; 14/14 self-test PASS; 10/10 plan tasks PASS) and **Tranche 5a-integration** (audit-log analyzer at `analyze-propagation-audit-log.sh` with `summary`/`cadence`/`unmatched`/`slow` subcommands — 7/7 self-test PASS; `/harness-review` skill Check 13 KIT-1..KIT-7 sweep; pilot-friction template at `templates/pilot-friction.md`; enforcement-map row + harness-architecture section + 5 narrative-doc citations; 8/8 plan tasks PASS). All closures via `close-plan.sh` with zero `--force`. Build Doctrine roadmap headline status v6 — 7 of 8 tranches DONE. **Pre-pilot infrastructure now complete** — Tranche 4 (canonical pilot) is the only structural wall remaining; pilot consumes a fully-wired substrate (doctrine + templates + propagation engine + audit log + ritual + sweep + analyzer + friction template). 5b/6b/7 gate on pilot evidence; 5c/6c/HARNESS-GAP-11 gate on 2026-08 telemetry. v29 — Autonomous Build Doctrine continuation push: shipped Tranches 2 (template schemas — 7 schemas + 7 examples + README, 10/10 PASS), 3 (template content — 22 universal-floor templates × 2 depths + 4 language naming + branching/commits + API-style architectural default + README, 15/15 PASS), and 6-scaffolding (Python orchestrator package — DAG state machine + state types + Dispatcher protocol + ~32 pytest tests + validation-gap README, 9/9 PASS). All closures via `close-plan.sh` with zero `--force`. Tranche 4 (canonical pilot) is the wall — needs user-side decisions: pilot project identity, readiness assessment, cross-repo access, Python-equipped environment for Tranche 6 scaffolding validation. Handoff doc at `docs/plans/tranche-4-canonical-pilot-handoff.md`. Tranches 5, 7, and Tranche 6 propagation engine all gate on Tranche 4 empirical signal per doctrine. Build Doctrine roadmap headline status v3 — 7 of 8 tranches DONE. v28 — REOPENED 4 plans (Tranche E, parent of Tranche 1.5, Tranche F, HARNESS-GAP-17) per user 2026-05-06: original 2026-05-05 closures used close-plan.sh --force bypassing per-task verification on every task; not actually completed. Status flipped COMPLETED → ACTIVE; plans moved back from `docs/plans/archive/` to `docs/plans/`. Re-closure must be genuine (close-plan.sh's --force flag has since been removed). v27 — Path A in flight: state-summary.sh hybrid shipped (4/4 self-tests PASS, demarcated DERIVED + LLM-SYNTHESIS regions); env-var "override" removed from close-plan.sh entirely (was theater for an LLM agent — "loud is not rare" per user 2026-05-06; 13/13 self-tests PASS); session-wrap.sh wired into Stop chain in prior session. Pending Path A item: start-plan.sh for task-start automation. Added HARNESS-GAP-22 — sweep harness for other --force / --no-verify / OVERRIDE-style escape hatches; remove or convert to friction-the-agent-cannot-satisfy. v26 — Tied off the previous session's loose ends in this brief follow-up session: committed `session-wrap.sh` + ADR 027 v2 (Layer 5: handoff-freshness-as-precondition); flipped 2 stale 2026-05-05 discoveries (codenames → implemented; multi-active-stranding → superseded by Tranche E); archived expired `architecture-simplification-gate-relaxation` policy. Master is now CLEAN (zero ACTIVE plans). Added HARNESS-GAP-19 — wire `session-wrap.sh` into Stop chain (script is built and self-tests 5/5 PASS, just not auto-invoked yet). Earlier v25 — **Tranche 1.5 (architecture simplification) substantively complete** in the prior session. 6 of 7 sub-tranches shipped: A (incentive redesign), B (mechanical evidence substrate), C (work-shape library), D (risk-tiered verification), E (deterministic close-plan procedure — **2.8 sec closure benchmark** vs 65K-token baseline), G (calibration loop bootstrap). Tranche F (failsafe audit) deferred to next session — depends on A-E being battle-tested first. ADR 026 (harness catches up to doctrine) + ADR 027 (autonomous decision-making process) + queued-tranche-1.5.md (14 pre-emptive decisions for async user review) + doctrine extensions N1/N2/N3 (now Anti-Principle 16, Principle 17, Principle 18 in `01-principles.md`) all shipped. Hard freeze on new failsafes in effect. Live acceptance test for close-plan.sh deferred to next session — closing the architecture-simplification plans themselves via the new procedure. Closure-validator (today's GAP-16 ship) tagged-for-retirement; Tranche F's first retirement target. 8 plans currently ACTIVE on master (parent + 6 sub-tranches + HARNESS-GAP-17), all substantively done, all closing via close-plan.sh in next session. v24 — HARNESS-GAP-08 (spawn_task report-back) + HARNESS-GAP-13 (hygiene-scan 4-layer expansion) BOTH IMPLEMENTED + auto-archived this session per Option B. 14 task-verifier PASS commits on `verify/pre-submission-audit-reconcile`. Also reconciled stranded pre-submission-audit-mechanical-enforcement plan; HARNESS-GAP-16 added as next-after pickup (closure-validation gate). v23 — HARNESS-GAP-17 Part A IMPLEMENTED in this session: all 5 user-facing narrative docs (README, harness-strategy, best-practices, quality-strategy, CLAUDE.md) updated to reflect Gen 5/6 + Build Doctrine integration arc; live `~/.claude/CLAUDE.md` synced. Part B (docs-freshness-gate narrative-doc extension) remains deferred per original P2 estimate. Earlier v22 — duplicate-numbering conflict resolved: narrative-docs-stale entry (originally tagged GAP-16 in v21) renumbered to **HARNESS-GAP-17**. GAP-16 is the closure-validation gate per the "Open work" pickup list. Both entries were added 2026-05-05 within 40 minutes; the v21 header tagged the docs-stale one GAP-16 first, then the closure-validation entry duplicated the number 40 min later — closure-validation kept as GAP-16 since the "Open work" section treats it as such. v21 — HARNESS-GAP-16 added — user-facing narrative docs (README, harness-strategy, best-practices, quality-strategy, CLAUDE.md) stale post-integration; docs-freshness-gate has narrative-doc blind spot. Earlier 2026-05-05 v20 — HARNESS-GAP-08 absorbed into `docs/plans/harness-gap-08-spawn-task-report-back.md` (per backlog-plan-atomicity rule). pre-submission-audit-mechanical-enforcement plan reconciled and auto-archived this session (was stranded ACTIVE since 2026-05-03 with all 5 tasks shipped but bookkeeping never run; see commits `588b6db` + `4e8f658` on `verify/pre-submission-audit-reconcile` branch). Earlier 2026-05-05 v19 — backlog header restructured for legibility; full version log moved to bottom of file. Phase 1d-G shipped 2026-05-04 (codename scrub + GAP-14-followups + observed-errors-first stub conversion all IMPLEMENTED). Two stale plans archived: `adversarial-validation-mechanisms.md` SUPERSEDED (mechanisms shipped piecemeal), `acceptance-loop-smoke-test-evidence.md` moved to archive (orphan evidence file).

Outstanding improvements to the Claude Code harness (rules, agents, hooks, skills). Project-level backlogs live in individual project repos; this file tracks harness-level work.

UI write path (ask-rooted-workstreams-p1, Task 15): the workstreams-ui Backlog pane (`neural-lace/workstreams-ui/web/backlog.js` + `GET`/`POST /api/backlog` in `server/server.js`) reads and writes rows in this file directly — adds append a well-formed row to "Open work — substantive deferrals"; SCHEDULE/DEMOTE/FOLD/WONTFIX dispositions append the same marker vocabulary the O.9 triage loop's parser already understands, row-scoped. No parallel store; this file stays the one source of truth either way.

## Next pickup (recommended)

**HARNESS-GAP-13 — harness-hygiene-scan expansion** is the next-cleanest pickup once GAP-08 ships. Full original scope per user 2026-05-05: ~9-10 hr; layers 1-4 (denylist additions + heuristic detection + periodic full-tree audit + sanitization helper).

In flight this session: GAP-08 (`docs/plans/harness-gap-08-spawn-task-report-back.md`) + reconciliation of stranded pre-submission-audit plan.

## Open work — substantive deferrals

- **PLAN-REVIEWER-CHECK19-3-UNRELATED-FAILURES-01 — `plan-reviewer.sh --self-test` fails 3
  Check-19 (intended-functionality restatement) scenarios on this machine, unrelated to any
  gated-pipeline-master-2026-08 Task 25 change** (found 2026-08-03 while re-running this file as a
  `review-chain-lib.sh` consumer suite; Task 25 made ZERO edits to `plan-reviewer.sh` — `git diff`
  confirms — and Check 19's own implementation, `adapters/claude-code/hooks/plan-reviewer.sh:1826`
  onward, references none of the files Task 25 touched). Failures: `ee3
  check19-pre-existing-warns-not-blocks` ("no WARN emitted"), `ee4
  check19-draft-to-active-flip-blocks` ("permanent-grandfather bypass is open"), `ee7
  check19-undecidable-warns-not-blocks` ("no UNDECIDABLE warn emitted"). The Checks 20-22 scenarios
  in the SAME suite (the actual `review-chain-lib.sh` consumer surface: `c20a`/`c21b`/`c22c`/
  `c2022d`/`c2022e`) all PASS, confirming this task's own diff is not the cause. Re-derive: `bash
  adapters/claude-code/hooks/plan-reviewer.sh --self-test 2>&1 | grep -E 'ee[347]\)'`.
- **STALE-PRE-STOP-VERIFIER-DOC-REFERENCE-01 — doctrine/planning-full.md's "Task Completion — Verifier Mandate" section still names `pre-stop-verifier.sh` as the Stop-hook enforcement mechanism, but that file is now a retired exit-0 shim** (`adapters/claude-code/hooks/pre-stop-verifier.sh:2` — "Retired to attic/ (Wave D.5, ADR 058 D5). Exit-0 shim ..."); the real live enforcement is `stop-verdict-dispatcher.sh` (aggregates work-integrity-gate/session-honesty-gate/bug-persistence-gate + end-manifest validation). Noticed while adding the OD-022 verify-obligation subsection alongside it (gated-pipeline-master-2026-08 Task 25); out of that task's scope to fix. Re-derive: `grep -rn pre-stop-verifier adapters/claude-code/doctrine/*.md`.
- **TWO-GATES-DEAD-LIVE-BECAUSE-THE-SYNC-NEVER-ADDED-THEIR-BODY-FILES-01 — `scope-enforcement-gate` and `concurrent-ownership-gate` currently FAIL OPEN on Misha-Laptop; their split-out `-body.sh` files were never deployed** (added 2026-08-03; label: `harness-gap`, `priority:high`; fold-in: the blocked-deploy review now in flight). **PROVEN by execution, not inference.** The other machine's Stage 0b work split both gates into a thin entry file plus a `-body.sh` sourced only when the command is relevant. The bodies landed in the repo; they were never copied into `~/.claude/hooks/`. Live result:
  ```
  scope-enforcement-gate.sh  line 230: .../scope-enforcement-gate-body.sh: No such file or directory   -> rc=1
  concurrent-ownership-gate.sh line 173: .../concurrent-ownership-gate-body.sh: No such file or directory -> rc=1
  ```
  **Only exit 2 blocks in this harness** (see [[project_pretooluse_exit2_blocking_semantics]]), so `rc=1` means both gates are ABSENT, not degraded: scope-enforcement (stops a builder writing outside its declared scope) and concurrent-ownership (stops cross-machine branch-delete and plan-flip collisions) are silently not running. **Why it went unnoticed:** a trivial command returns `rc=0` because that is the fast path which never sources the body — so any smoke test that does not use a *relevant* command reports the gate healthy. Both were verified healthy-looking with `echo hi` and broken with `git commit` / `git branch -D`. **Second, distinct defect:** `session-start-auto-install.sh` is documented as continuously syncing live from origin/master, and the 2026-08-03 master handoff describes that sync as "additive-only and cannot remove or narrow" — but here it failed to perform an ADD. A sync that cannot introduce a NEW file cannot deploy any entry/body split, which is the estate's current refactoring pattern. Whether that is by design or a defect is unresolved and matters, because more splits are planned. **Third, a genuine safety-vs-safety deadlock worth naming:** `install.sh`'s review-before-deploy gate correctly blocks the very deploy that would close this hole, because eight files (including both bodies) lack PASS records at their current blob SHAs. All eight have prior records at OLDER SHAs, so the gate is behaving exactly as designed — content changed, re-review required. The resolution is a real review, not a bypass, and one is dispatched. But the class is worth recording: *a deploy gate can hold a fix for a broken gate, and nothing measures how long the hole stays open.* **Re-derive:** pipe a `git commit`-shaped PreToolUse payload into `~/.claude/hooks/scope-enforcement-gate.sh` and check for the sourcing error; compare against an `echo hi` payload, which will falsely look healthy.

- **LIVE-MIRROR-DRIFT-IS-UNMEASURED-BETWEEN-DOCTOR-RUNS-01 — 7 of 115 live hooks differed from the repo, and the only signal was a doctor RED nobody had acted on** (added 2026-08-03; label: `harness-gap`, `priority:medium`; fold-in: the health-tick starvation lane, since a starved doctor step is part of why this stayed invisible). **PROVEN:** a direct `cmp` sweep of `adapters/claude-code/hooks/*.sh` against `~/.claude/hooks/` found 7 of 115 divergent — `gh-merge-canonical-gate.sh`, `harness-hygiene-scan.sh`, `review-record-push-gate.sh`, `session-start-auto-install.sh`, `session-start-digest.sh` differing, and `concurrent-ownership-gate-body.sh`, `scope-enforcement-gate-body.sh` **missing entirely** — plus `~/.claude/manifest.json` at a different sha256 from the repo's. A prior reviewer surfaced this as a doctor RED ("live manifest does not match repo — run install.sh") and it was carried as a note rather than acted on. **Why it matters beyond the two dead gates:** every doctor verdict, every gate behaviour, and every measurement taken on this machine is a measurement of the LIVE tree, while every review and every self-test is run against the REPO tree. When they diverge, a green suite and a broken machine are fully compatible — which is precisely what happened here. **Fix direction:** drift should be a first-class, cheap, continuously-measured number (count of differing files), surfaced at SessionStart, not a side effect of a doctor step that can be starved out of its budget. **Re-derive:** `for f in adapters/claude-code/hooks/*.sh; do b=$(basename "$f"); cmp -s "$f" ~/.claude/hooks/"$b" || echo "DIFF/MISSING $b"; done`.

- **PATH-SHIM-IN-SELFTEST-HID-THE-PRODUCTION-BUG-IT-WAS-MEANT-TO-CATCH-01 — a CI-greening fix shimmed `stat` inside the self-test's PATH while ten production reads stayed GNU-only, so the test can no longer fail on the defect it exists to detect** (added 2026-08-03; label: `harness-gap`, `priority:high`; fold-in: the stat-class landing review now in flight). **PROVEN by direct read of master.** `adapters/claude-code/hooks/plan-edit-validator.sh:1135-1142` generates a `$F16_BINSHIM/stat` wrapper — `if [[ "$1" == "-c" && "$2" == "%Y" ]]; then shift 2; /usr/bin/stat -c %Y "$@" 2>/dev/null || /usr/bin/stat -f %m "$@"; else /usr/bin/stat "$@"; fi` — and puts it on the self-test's PATH. Meanwhile **ten production reads** remain in the bare form `mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)` at `:175, :478, :653, :685, :828, :853, :1660, :1689, :1728` (+1). Because scenarios F16-F19 run under the shimmed PATH, they never exercise the real read — so the suite is green on a machine where the production path would fail. **Consequence on macOS:** `stat -c %Y` is not a valid BSD invocation, the `|| echo 0` fires, mtime reads 0, and every evidence-freshness comparison is made against the epoch — the check degrades to always-fresh (or always-stale) silently, meaning **no plan-task flip could ever be correctly authorized on a darwin machine**. This is not hypothetical for this estate: it runs two Windows machines and a Mac mini. **THE CLASS, which is why this row exists and is rated high:** a fix that makes the TEST pass by adjusting the test's environment, rather than making the CODE correct, is strictly worse than no fix — it converts a detectable defect into an undetectable one and consumes the alarm that would have surfaced it. A test harness may never shim a dependency whose behaviour is the thing under test. **Re-derive:** `grep -n 'stat -c %Y' adapters/claude-code/hooks/plan-edit-validator.sh` (bare production reads) vs `grep -n 'BINSHIM' adapters/claude-code/hooks/plan-edit-validator.sh` (the shim). **Related, same commit family:** `workstreams-read.sh:912,915,923` — scenario R19 compared 0 to 0 and PASSED without the fast path ever engaging, the same shape in a different file.

- **HEALTH-TICK-STEP-STARVATION-1194-SILENT-SKIPS-01 — one greedy step eats the whole 300s budget and every step behind it is skipped, permanently** (added 2026-08-03; label: `harness-gap`, `priority:high`; fold-in: IN FLIGHT as a dedicated lane). **PROVEN from `~/.claude/state/health-tick/tick.log` on Misha-Laptop:** **500 occurrences of `rc=124`** (step timeout) and **1,194 occurrences of `budget exhausted`**. Most recent run: `doctor-cache-refresh rc=1 elapsed=10622ms` · `scheduled-task-health rc=0 20018ms` · `heartbeat-reap rc=0 27318ms` · **`worktree-prune rc=124 elapsed=237679ms`** · `SKIP perf-snapshot: budget exhausted` · **`done in 397s (budget 300s)`**. Two properties make this a SCHEDULING defect rather than a slow-step defect: (1) **the culprit rotates** — an earlier capture had `doctor-cache-refresh` at 308s starving `worktree-prune`, here it is exactly reversed — so whatever sits at the back of the queue is starved on nearly every run; (2) **the global budget is not actually enforced** — 397s against a declared 300s. **Downstream consequence, the reason this was found:** the Loop-2 pressure tick lives behind the starvation, so all **5,830 of 5,830** rows in `~/.claude/state/governor/ledger/Misha-Laptop.jsonl` read `"pressure_src":"absent"` — it has never once emitted a real value, which makes the Accountable Estate Program's T6 prerequisite (d) FALSE despite its commit having landed (see the corrected CLEARED line in `docs/plans/accountable-estate-program-2026-07.md`). Separately `pts_run_tick` measures ~14m50s and could never fit a 300s budget under any scheduler, so fair scheduling alone will not rescue that step — it likely does not belong on a 300s tick at all. **Fix direction (dispatched):** per-step bounds via `nl_run_bounded` (`hooks/lib/portable-timeout.sh:182`), a no-starvation guarantee (rotation / deficit round-robin / persisted skip-debt), an actually-enforced global budget, and audible skips — 1,194 silent ones is how this survived. **Explicitly NOT the fix:** raising the budget, which trades a visible failure for a slower invisible one on an already fork-starved machine. **Re-derive:** `grep -c 'rc=124' ~/.claude/state/health-tick/tick.log; grep -c 'budget exhausted' ~/.claude/state/health-tick/tick.log`.

- **SPAWN-TIME-SUPERSESSION-CHECK-IS-CONVENTION-NOT-MECHANISM-01 — three builder-sessions were dispatched at work master already had, in a single day, because the prescribed pre-dispatch check is a doctrine sentence nobody executes** (added 2026-08-03; label: `harness-gap`, `priority:high`; fold-in: IN FLIGHT as a dedicated lane). **Golden case, three PROVEN instances on 2026-08-03, all orchestrator-side:** (1) `docs/handoffs/2026-08-03-MASTER-HANDOFF-process-integrity.md` listed F1/F2/F5/F6 as unfixed, so two builders were dispatched at them — master had fixed all four hours earlier (`9d3afbb9` sf_release + watchdog identity-verified kill, `d46beee5` verdict-cache single-writer, `be5e4273` friction-ledger unification), verified by `git merge-base --is-ancestor`; (2) a builder was dispatched at T6's four prerequisites from the task text in `docs/plans/accountable-estate-program-2026-07.md`, while **the same file, ~60 lines higher**, recorded "CLEARED 2026-07-29: T6 prerequisites (a)(b)(d) — landed as 5ee67c2 + 1cdef7f + 4fdfc83" (all three ancestors of master); (3) a doctrine-compact trim was dispatched that master had already landed as `d6e70175` + `ccfed944` — that lane correctly REFUSED to land its rebuilt version (it would have deleted newer HR-F11 content) and spent its budget auditing the landed trim instead, salvaging two genuinely-dropped doctor check names (`a0d8e322`). **Root cause is one thing, not three:** the orchestrator reads the artifact DESCRIBING the work and dispatches, without asking master whether the work is already done. **The remedy is already documented and already inert** — `doctrine/estate-coordination-full.md` prescribes "the spawn-time supersession check (grep master + sibling branches before dispatching)" and **nothing calls it**, exactly like `agent-heartbeat.sh emit` (see [[AGENT-LIVENESS-IS-CONVENTION-NOT-MECHANISM-01]]). Constitution §10's cardinal defect: documented enforcement that does not fire. **Fix direction (dispatched):** `workstreams-emit.sh --on-builder-dispatch` is already wired on the PreToolUse `Task|Agent|Workflow` matcher (`settings.json.template:351-355`) and **already parses the NL-ATTRIBUTION plan+task header** — so the plan slug and task id are in hand at the exact moment of dispatch. WARN (never block: legitimate re-dispatch at a done task exists — remediation rounds, verification — and a blocking gate here would be tuned out, as `review-record-commit-gate` was after 78 overrides). Cost is the hard constraint: this is the PreToolUse path of every dispatch, `merge-base --is-ancestor` is a fork, and this estate has already self-DoS'd from that shape. **Re-derive:** `rg -n "supersession" adapters/claude-code/` — hits doctrine prose only, zero call sites.

- **DOCTRINE-COMPACT-TRIM-DROPPED-TWO-LIVE-MECHANISM-NAMES-01 — the CI-driven 3000-byte trim silently removed two wired doctor check names from the doctrine corpus** (added 2026-08-03; label: `harness-gap`, `priority:medium`; FIXED same day as `a0d8e322`, row kept for the class). **PROVEN:** after master's compact trim (`d6e70175`, `ccfed944`), `check_review_surface_cross_check` (`adapters/claude-code/hooks/harness-doctor.sh:3509`) and `check_review_reviewer_independence` (`:3774`) both still existed as live wired functions, while `grep -rl` over `adapters/claude-code/doctrine/` returned **zero** files naming either — the concepts survived the trim, the mechanism NAMES did not. Found by an atom-level audit (every backtick-quoted atom in each pre-trim compact must survive somewhere in the post-trim corpus): 12 candidates flagged, 10 were false positives (cross-file moves, or supersessions where the paired `-full.md` is strictly richer), 2 were genuine losses. Restored into `doctrine/review-before-deploy-full.md`; no compact grows, so the cap stays satisfied and the golden check stays green (`Checks passed: 4`, rc=0, re-verified independently). **The class, which is the reason this row exists:** a size-cap trim is a lossy transform driven by a check that measures BYTES and cannot see MEANING, so it will silently drop the least-verbose thing on the page — which is exactly what a mechanism name is. Any future compact trim needs the atom-level conservation audit as part of its done-bar, not as an afterthought. **Re-derive:** for each wired `check_*` function name in `harness-doctor.sh`, grep its kebab-case form across `adapters/claude-code/doctrine/`; a zero means the corpus no longer names a mechanism the doctor runs.

- **SETTINGS-TEMPLATE-GRANDFATHER-FIXTURE-MISSING-CUTOVER-REF-01 — session-start-auto-install.sh's Scenario 18 (CANON3) grandfather-manifest.json fixture has the same stale-fixture-vs-lib-contract gap that Scenario 16 (CANON2) had before today's CI-triage fix, just not yet exercised by any assertion** (added 2026-08-03 from the CI triage that fixed Scenario 16's `review-gate-skips-uncovered-fresh-install`; label: `harness-gap`, `priority:low`; fold-in: the next touch of `session-start-auto-install.sh`'s self-test, or a dedicated small task). **PROVEN:** `adapters/claude-code/hooks/session-start-auto-install.sh` line ~953 (`CANON3`, Scenario 18's `settings.json.template` review-gate test) writes a `grandfather-manifest.json` with NO `cutover_ref` field, the exact shape `lib/review-record-gate-lib.sh`'s own self-test pins as "honored for nothing" (harness-reviewer C2-A). Scenario 18 only asserts the UNCOVERED path (the template is deliberately bumped to an unreviewed v2 before the assertion), so the missing `cutover_ref` is currently inert — nothing in this fixture ever needs `rrg_is_covered` to return true. If a future scenario is added here to test the POSITIVE "reviewed template merges normally" path, it will fail exactly as Scenario 16's `covered.sh` did until `cutover_ref` is added, via the same two-commit pattern session-start-auto-install.sh's `$CANON2` fixture now uses (commit the content first, record that commit's sha as `cutover_ref`, then commit the manifest that cites it). **Re-derive:** `grep -n cutover_ref adapters/claude-code/hooks/session-start-auto-install.sh` (currently only the `$CANON2`/Scenario-16 fixture, added by this triage, will match).

- **AGENT-LIVENESS-IS-CONVENTION-NOT-MECHANISM-01 — the cockpit is structurally incapable of showing a running background agent, because nothing ever calls the heartbeat emitter** (added 2026-08-03 from the operator's fourth report of this same surface; label: `harness-gap`, `priority:high`; fold-in: IN FLIGHT as a dedicated lane against cockpit-roadmap-redesign T11). **PROVEN by measurement 2026-08-03 with seven agents genuinely running:** (1) `~/.claude/state/heartbeats/agents/` **does not exist at all** — the parent dir held exactly two live files (this session's heartbeat and a stale `probe-sid.json`) plus an orphaned atomic-write temp `*.json.iqLTc8` from 2026-07-23 that nothing ever reaped; (2) `rg` over the whole repo finds `agent-heartbeat.sh`'s `emit`/`conclude` verbs referenced in exactly TWO places — `doctrine/background-work-tracking.md:36-37`, which *describes* the convention, and the script's own header at `:37`/`:43`. **No hook, no dispatch path, no wrapper calls it.** So the namespace is never created, `deriveLiveAgentLeaves` (`neural-lace/workstreams-ui/server/derive-lib.js` ~:800-970) has nothing to read, and `running_now` can never name an agent. `manifest.json`'s own `agent-heartbeat` entry concedes this — "INTERIM PATTERN: relies on the dispatched agent calling emit/conclude". **This is constitution §10's cardinal defect: documented enforcement that does not fire.** **Fix direction (dispatched):** liveness must be a side effect of the agent doing work — a PreToolUse hook fires *inside the agent's own session*, so stamping a heartbeat there makes every agent heartbeat automatically with zero reliance on the agent choosing to. Constraints that make it non-trivial: it runs on every tool call, so the hot path must be spawn-free (this estate has already had a self-DoS from exactly that shape); the namespace must be reaped (a prior heartbeat reaper was itself dead on arrival, 2026-07-09); and a killed agent that never reaches `conclude` must still expire. **Re-derive:** `ls ~/.claude/state/heartbeats/agents/ 2>&1; rg -n "agent-heartbeat.sh (emit|conclude)" adapters/`.

- **SESSION-HEARTBEAT-STALE-WHILE-SESSION-ALIVE-01 — the main-session heartbeat stopped updating ~9 hours into a demonstrably live session** (added 2026-08-03, found while diagnosing the row above; label: `harness-gap`, `priority:medium`; fold-in: the agent-liveness lane, as its second finding). **PROVEN:** `~/.claude/state/heartbeats/d3059d78-d536-48b1-89d4-d9e58b2f2d08.json` last written 2026-08-03T00:16 while the session was still actively running tool calls at 09:13 — a ~9-hour staleness on a session that never stopped. Under `classifyHeartbeatAge`'s 30-minute `activeMs` bound that session classifies as long-dead. Distinct from the row above (which is about agents having no namespace at all); this one is the *session* half degrading. Not yet root-caused — candidates are the write path failing silently or the emitting hook no longer firing on this session's event mix. **Re-derive:** compare the heartbeat file's mtime against the session's actual last tool call.

- **ORPHAN-DOCTRINE-FILE-CAN-NEVER-SATISFY-THE-INDEX-CHECK-01 — the INDEX generator and the CI checker disagree about what must be indexed, so one doctrine file makes master permanently red and regenerating cannot fix it** (added 2026-08-03 from the CI re-green work; label: `harness-gap`, `priority:medium`; fold-in: the CI re-green lane, or the next manifest edit). **PROVEN:** `evals/golden/rules-index-coverage.sh` requires EVERY non-`-full` `doctrine/*.md` to have a row in `doctrine/INDEX.md` (matched as `](<basename>)`), but `manifest-check.sh --gen-index` emits one row **per manifest ENTRY**, using that entry's `doctrine_file` field. A doctrine file that no entry points at therefore cannot receive a row from the generator, and the file is marked do-not-hand-edit. `deterministic-process.md` is exactly this case: it appears in `manifest.json` five times but only inside *prose* (`golden_scenario` / `honest_status` text), and **zero** entries name it as their `doctrine_file` (verified by walking all 157 entries; 54 distinct doctrine files are referenced). Regenerating the index fixed 10 of the 11 missing rows and structurally could not fix the 11th. **Fix:** either point a relevant entry at `doctrine/deterministic-process.md` (the review-record push-gate trio all currently name `doctrine/review-before-deploy.md`, and `deterministic-process.md` Rules 1 and 2 are cited in their own text, so one of them is the natural owner), or teach the generator to emit rows for unreferenced doctrine files. **Generalization:** any generated artifact whose *checker* has a broader domain than its *generator* produces an unfixable red. **Re-derive:** `node -e` over `manifest.json` counting entries whose `doctrine_file` contains `deterministic-process`.

- **NL-ESTATEJANITOR-FAILING-EVERY-FIVE-MINUTES-01 — a scheduled task nobody is watching has been returning a non-zero result on a 5-minute cadence** (added 2026-08-03; label: `harness-gap`, `priority:medium`; fold-in: the Phase-A activation preflight, or any maintenance-layer lane). **PROVEN:** `Get-ScheduledTaskInfo -TaskName NL-EstateJanitor` on Misha-Laptop reports `LastTaskResult = 2147946720` (`0x800710E0`), `NumberOfMissedRuns = 0`, next run 5 minutes out. `[System.ComponentModel.Win32Exception]` cannot decode that HRESULT to a standard system message, so the meaning is NOT established and is deliberately not guessed here. **Not diagnosed** — recorded because a task failing every five minutes on the machine that collects estate occupancy data is not benign, and it appears in no inventory. **Related correction:** the 2026-08-03 master handoff states "the five legacy `NL-*` tasks are Disabled"; on this machine four of six are ACTIVE (`NL-CoordSync`, `NL-EstateJanitor`, `NL-health-tick`, `NL-SupervisorTick`), so any estate-wide reasoning from "maintenance is off" must be re-derived per machine. **Re-derive:** `Get-ScheduledTaskInfo -TaskName NL-EstateJanitor | Format-List`.

- **NEEDS-YOU-RESOLVE-IS-WHY-ASKS-GO-STALE-01 — retiring one satisfied operator ask takes over two minutes, so no normal session can afford to do it** (added 2026-08-03; label: `harness-gap`, `priority:medium`; also filed to the machine-wide ledger via `nl-issue.sh`; fold-in: the process-integrity phase, alongside the operator-directives register — that register is a WRITE mechanism and this proves the estate's existing write mechanism is unusable at interactive speed). **PROVEN:** `needs-you.sh resolve <id>` exceeded a 120-second timeout on a **70-item, 53 KB** ledger; a `bash -x` trace shows it reaching `git rev-parse --git-common-dir` (itself 1.5 s in this 50-worktree repo) and then spending the remaining budget in the full re-render. Four resolves had to be moved to a background shell to complete. **Consequence, demonstrated the same day:** six open operator asks were already satisfied and had simply never been re-checked — four scheduled-task registrations (all verified registered, `NeuralLace-HarnessEvaluator-Daily` proven firing `rc=0`), one duplicate, and one asking the operator to fix a GitHub Actions billing failure that **does not exist** (run `30797446442` concluded SUCCESS; the red X is a real test failure). **Second, separate defect:** running `needs-you.sh` with no arguments prints `line 2251: render: command not found` before its usage text — a bare `render` word where a verb dispatch was intended.

- **TASK-OUTPUT-SIZE-IS-NOT-A-LIVENESS-PROXY-01 — I killed three live agents by treating a 0-byte task-output file as "never started"** (added 2026-08-03; label: `harness-gap`, `priority:medium`; fold-in: the agent-liveness lane — this is the orchestrator-side twin of that row). **What happened:** asked whether long-running background agents were still doing anything, I ranked them by their task-output file's size and mtime. Seven read `size=0` with mtimes 6-9 hours old, so I concluded they had never started and stopped five of them. **The proxy is invalid:** the task-output file is not written incrementally — it lands when the agent finishes, so a 0-byte file means "still running OR never started" and its mtime is merely its creation time. The kill notifications proved it: those agents were mid-work ("Now the consumer side in `nl-maintenance.sh`", "S8 flaked: with ~3 s per spawn, the test sequence itself exceeds the 120 s lock TTL"). Two had uncommitted edits in their worktrees that were nearly lost. Recovered by resuming each from its transcript via SendMessage. **Two durable lessons:** (1) the ONLY sound liveness signals available to an orchestrator today are git activity on the agent's branch and the agent's own heartbeat — and the heartbeat is exactly what AGENT-LIVENESS-IS-CONVENTION-NOT-MECHANISM-01 proves does not exist, so the orchestrator is currently flying blind by construction; (2) dispatch prompts must instruct builders to commit at every milestone, because uncommitted worktree work is invisible to the orchestrator and unrecoverable if the process dies.


- **CI-RESULT-CONSUMPTION-GAP-2026-08-03-01 — nothing in the harness reads GitHub CI results; two workflows red on every master push since 2026-08-02T21:28Z while sessions kept pushing** (added 2026-08-03, operator-named; label: `harness-gap`, `priority:high`; fold-in: the gated-pipeline merge-train integration commit for parts b/c, the in-flight CI-triage builder for part d). Evidence: last "Hooks self-test" success 2026-08-02T21:28:51Z, ~23 consecutive failures since (gh run list); push output prints `Required status check "validate" is expected` and no mechanism consumes it — the mandatory-writes/voluntary-reads class applied to CI. Fix set: (a) orchestrator-pattern post-push CI check step (doctrine), (b) doctor check surfacing latest master CI conclusion per workflow (WARN on red, digest-visible), (c) register entry OD-021 ci-is-read-mandatory, (d) root-cause the two red workflows (builder in flight; one identified failure: gate --check scenario `20 check-mode-would-block-same-fields-no-ledger-write` rc=2 on the Linux runner — cross-platform mask candidate). Session-behavior fix already active (memory file `feedback_check_ci_after_push`). Re-derive: `gh run list --repo mishanovini/neural-lace --limit 8`.

- **PREDECESSOR-CLOSURE-CARRYFORWARDS-2026-08-03-01 — five items with no successor-plan owner, registered at the harness-execution-redesign SUPERSEDED flip so the archive loses nothing** (added 2026-08-03 by the gated-pipeline orchestrator from the closure verification in `docs/plans/archive/harness-execution-redesign-2026-08-evidence.md` §"Closure verification under supersession"; label: `harness-gap`, `priority:medium`; fold-in: per-item below). The predecessor's T1 closed PASS; T2 FAIL / T3 INCOMPLETE with these exact unowned gaps: (1) **Doctor gate-message lint** (T2's own outcome arbiter, "lint 5/5" unmeetable without it) — NOTE this is ALSO a design→plan fidelity slip in the successor: design r3 §9 dispositions S-29→REQ-A5 but successor T7's task text never carried it; candidate owner: fold into successor T14 (plan-reviewer Checks 20-22 work, same file family) or a dedicated small task; the fidelity re-review at T16 should catch this class going forward. (2) **Contract fields on the five retrofitted gates' manifest entries + a gate-contract convention section in harness-dev.md** (T2 Docs impact, jq-verified absent). (3) **Workaround-rate threshold → nl-issue.sh auto-file** (D-04's auto-file leg; either build at the T20 carriage work or record an explicit design-cut). (4) **harness-dev.md install/uninstall/rollback runbook section + workstreams-ui README dashboard note** (T3 Docs impact; natural owner: successor T10 registration work). (5) **T2/T3 Comprehension Articulations** if either archived task is ever to flip post-archive (Decision 020d holds; articulations must be graded against e5432f3c-era diffs). Re-derive: read the closure-verification section in the archived evidence file.

- **BRANCH-SALVAGE-2026-08-01 — six unmerged branches hold work master genuinely lacks; the other 56 are proven-superseded and delete-eligible** (added 2026-08-01 from the branch-disposition sweep; label: `harness-gap`, `priority:medium`; fold-in: one lane per row below, highest-value first). Full evidence table + per-branch citations: `docs/reviews/2026-08-01-branch-disposition-sweep.md`. **Why this took a manual pass:** this repo squash-merges, so `git cherry` patch-ids and "unmerged" branch status are both near-meaningless here — 40 of 74 branches had >=90% of their added lines already verbatim on master, and 24 had a commit subject present in master's log under a different SHA. The mechanical purge (`purge-verified-20260729.sh`) correctly refused to touch any of them, which is why it exhausted at 3 removals. The six salvage rows:
  1. **SWEEP-SQUASH-MERGE-VISIBILITY-01** (`feat/sweep-squash-merge-visibility`, tip `e7e10f3`) — ~470 lines teaching `scripts/worktree-hygiene-sweep.sh` to recognise a squash-merged branch as PROVEN-MERGED via merged-PR lookup (`load_merged_prs`, `lookup_merged_pr`), plus its 2026-07-17 harness-review fixes (1 Critical, 3 Major, 2 Minor). Master's sweep has ZERO squash-merge visibility — this branch is the mechanism that makes the whole class above self-service. **Highest-value salvage in the estate; land this before the next sweep.**
  2. **RECLAMATION-PROPOSAL-AMENDMENT-01** (same branch; `docs/reclamation-proposal-amendment`'s 2 commits are its ancestors) — an unlanded 124-line amendment to `docs/proposals/2026-07-08-worktree-branch-reclamation.md`: root-cause 1 refuted, the operator decisions (keep the approval channel; expiry SURFACES, never destroys) and 7 edge cases learned from the first real sweep. Master still carries the un-amended 92-line original. Salvaging row 1 covers this; delete `docs/reclamation-proposal-amendment` only AFTER that lands.
  3. **PREPUSH-PII-PATTERN-CLASS-01** (`salvage/pre-push-pii-patterns-20260702`, tip `0a44e69`) — SECURITY-RELEVANT: ~131 lines adding a PII/SSN pattern class to `hooks/pre-push-scan.sh`, a `sensitive-patterns-allowlist.local.example`, and `docs/harness-improvements/001-stop-gate-reflective-escalation.md`. None on master; the credential scanner still has no PII class.
  4. **RESUMER-JQ-BROKEN-NOT-ABSENT-01** (`claude/dreamy-mclaren-6f2ac3`, tip `fbbfc19`) — fixes a latent defect master STILL has: `scripts/session-resumer.sh` treats `command -v jq` as proof jq WORKS, so a present-but-broken jq silently drops digest-feed lines and TRUNCATES `write_backoff_state`'s file (`jq ... > "$path"` truncates before failing). Fix builds the line first and falls back to manual JSON on any failure.
  5. **EVENT-DRIVEN-HEARTBEAT-BEAT-MODE-01** (`feat/event-driven-heartbeat`, tip `9ff78f6`) — an unlanded `--beat` event-driven heartbeat mode for `workstreams-emit.sh` (+ self-tests + frozen spec) meant to replace the polling scheduled task; master still polls via `--heartbeat`. Treat as a DESIGN to re-evaluate against today's `session-heartbeat.sh`/`health-tick.sh`, not a patch to cherry-pick — 9 weeks of divergence. (Its other half, workstreams tree real-nesting, already landed as `3da37b1`.)
  6. **OPERATOR-TODO-FIXTURE-POLLUTION-REVIEW-01** (`claude/infallible-montalcini-26a8f0`, tip `2bb52d0`) — a 64-line review, `docs/reviews/2026-07-13-operator-todo-fixture-pollution.md`, correcting an earlier misdiagnosis of operator-todo fixture pollution. Absent from master; cheap to preserve, and this is the kind of correction that gets re-learned expensively.
  **Two judgment calls the operator can overrule cheaply:** `claude/interesting-lederberg-3ad04d` was called ABANDONED (a one-line manifest edit removing `hooks/lib/sessionstart-singleflight.sh` from a `hooks[]` array, contradicting the 32-place convention) — if `harness-doctor.sh` actually flags that entry it flips to SALVAGE, and one doctor run settles it. Four ACTIVE-LANE branches sit on the <3-day boundary with 94-98% of content already on master; kept this pass, sweepable next.

- **EMIT-REPLAY-THIRD-SILENCED-STATE-WRITE-01 — the debounce-token write is the one `|| true` site the defect-4 sweep missed, and its comment misstates the failure direction** (added 2026-08-01 from the round-7 review of the emitter transport, finding F2; label: `harness-gap`, `priority:medium`; fold-in: the next touch of the replay subsystem, or a dedicated sweep of the idiom). **PROVEN by direct probe of the extracted `_dispatch_replay_token`** (reviewer's evidence): the mkdir-fails path returned two DIFFERENT tokens (fails open), the token-write-fails path returned two DIFFERENT tokens (fails open), and the healthy control returned the SAME token (dedups). The subsystem has THREE state writes; `bf5ddad` fixed two (`workstreams-emit.sh:688-703` spawn, `:3960-3985` builder) and left the third — the debounce token at `:3674` (`>"$f" 2>/dev/null || true`) and its mkdir fallback at `:3654` — still silenced, failing open with NO WARN. The rationale comment at `:3641` asserts the fallback is "merely conservative", which is TRUE for the noclock branch and FALSE for the unwritable-state-dir branch. **Fix:** correct `:3641` to distinguish the two fallback directions, and either capture the write status the way the other two sites now do or record this site as a named residual in the same comment. **Reachability caveat, stated honestly:** this layer only decides anything once the identity ledger (layer 1) has already failed, so the practical exposure is narrow — but the CLASS (silenced state write fails open invisibly) is exactly the one the commit set out to close, and a partial sweep leaves it alive behind a fixed instance. **Re-derive:** `rg -n '>>?\s*"\$[a-z_]+"\s*2>/dev/null\s*\|\|\s*true' adapters/claude-code/hooks/workstreams-emit.sh adapters/claude-code/hooks/plan-lifecycle.sh`.

- **MANIFEST-SUPPRESSION-CLAIM-OUTLIVED-ITS-EXCEPTION-01 — `manifest.json`'s dispatch-provenance entry states an unconditional suppression the emitter now PROVES has a condition** (added 2026-08-01 from the round-7 review, finding F3; label: `harness-gap`, `priority:medium`; fold-in: the next manifest edit, or any commit touching the dispatch-provenance unit). The entry's `honest_status` says **"Both sinks are suppressed for a REPLAYED dispatch identity"** with no qualifier, while `bf5ddad` proved (RED/GREEN, ledger path pre-created as a directory) that an unwritable ledger makes the gate **fail open** — the duplicate IS re-emitted, so the sinks are NOT suppressed in that case. Constitution §10: every mechanism claim in the enforcement inventory must be true at runtime. **Deliberately NOT fixed in that commit:** `manifest.json` is outside its declared two-file scope and editing it would have tripped `scope-enforcement-gate.sh` — the same discipline that correctly sent the TAKEOVER-brief correction to a backlog row instead of a scope stretch. **Fix:** amend the sentence to "…suppressed for a REPLAYED dispatch identity **whose identity write succeeded**; an unwritable ledger fails open (see EMIT-REPLAY-FAIL-OPEN residual)". **Re-derive:** `git show HEAD:adapters/claude-code/manifest.json | grep "Both sinks are suppressed"`.

- **RESTATE-COUNTS-RULE-OVERREACHES-ONTO-IMMUTABLE-RECORDS-01 — the standing count-restatement rule, as written, demands rewriting dated review records** (added 2026-08-01 from the round-7 review, finding F4; label: `harness-gap`, `priority:low`; fold-in: next edit of the STANDING RULE block at `docs/backlog.md`). The rule says restate every count "in every artifact quoting one". Taken literally that includes `docs/reviews/2026-07-31-integration-merge-consolidated-review.md:70,79,81` and `docs/reviews/records/2026-08-01-harness-change-review-4586088a.json` — immutable dated artifacts whose whole value is being a snapshot of what was true when written; rewriting them would corrupt the record. The rule's own author correctly did NOT rewrite them, which means the shipped practice already contains an unstated exception. **Fix:** add the exception inline — "…in every artifact quoting one AS A PRESENT-TENSE CLAIM; dated snapshots and immutable review records are exempt when labelled as such, and an out-of-scope artifact gets a fold-in row instead." **Generalization:** a standing rule whose first application requires an unstated exception should ship with that exception, or the next reader reads the correct deviation as a violation.
- **POST-MERGE-REVIEW-ADVISORIES-20260731-01 — six Minor advisories from the consolidated post-merge review of integration merge 301e35f, deferred not dropped** (added 2026-07-31; label: `harness-hygiene`, `priority:low`; fold-in: next hygiene sweep, or the takeover lane whose file each touches). Source: the 9-agent consolidated review (verdict FAIL on two Majors, both fixed in the remediation commit that added this row; these six are the non-blocking residue). (1) Merge 301e35f committed four runtime session-state files from the wip side — `adapters/claude-code/.claude/state/stop-hook-retries-*.txt`, `unresolved-stop-hooks.log`, one more under workstreams-ui — remove from tracking + gitignore the state dirs. (2) `hooks/workstreams-emit.sh` is mode 100644 while every sibling hook is 100755 (^2 had 755; inert today — all call sites use `bash <file>` — likely core.filemode=false artifact; align when convenient). (3) `scripts/close-plan.sh` S30 reuses variable name `D22` from an earlier scenario — legal and non-contaminating, but a future splice hazard; rename to D30 on next touch. (4) `hooks/lib/admission-lib.sh:1660` dead `rc=$?` (inherited byte-for-byte from ^2, not merge damage). (5) Suite-baseline correction: the pre-merge briefing numbers (admission-lib "67 scenarios", needs-you "53") match no tree state; the merged-tree oracle numbers are admission-lib 31 scenarios/80 assertions, needs-you 61/0, perf-tick 28/0, emit 123/123, close-plan 30 scenarios, janitor 22/22, brief 34/34 — use THESE as baselines, never re-propagate 67/53. **emit SUPERSEDED 2026-08-01: `131/131`, SUPERSEDED AGAIN 2026-08-03: `140/140`** (re-derive: `HARNESS_SELFTEST=1 bash adapters/claude-code/hooks/workstreams-emit.sh --self-test | tail -2`). The commit that transported `f018623`+`ab8055b` added the 8 defect-4 regression assertions RPL9-RPL9g, so 123 is now a HISTORICAL SNAPSHOT (2026-07-31 merged-tree oracle) and 131 was the next present-tense baseline; Task 15 (REQ-B14, gated-pipeline-master-2026-08.md, 2026-08-03) added 9 more (DL1-DL7 dispatch-ledger writer scenarios), making 140/140 the current present-tense baseline — every other figure in this list is untouched by that commit. (6) Four `{ source lib; } || true` guards at emit :84/:90/:92/:142 share the brace-group set-u hazard in BOTH parents but cannot be subshelled (source must mutate the shell) — inherent residual, recorded so nobody re-finds it; a fix would need a different guard idiom (e.g. pre-flight `bash -n` + existence check).
- **TAKEOVER-BRIEF-EMITTER-RESUME-POINT-STALE-01 — `docs/TAKEOVER-2026-07-31.md` §2b still tells the next machine to do work that is now DONE, and prescribes a probe that cannot work here** (added 2026-08-01; label: `harness-hygiene`, `priority:medium`; fold-in: the next touch of the takeover brief, or whichever plan adopts that file — **no active plan declares `docs/TAKEOVER-2026-07-31.md` in scope**, which is why the correction is recorded here instead of applied there: `scope-enforcement-gate.sh` correctly blocked staging it alongside the emitter transport, and stretching an unrelated plan's scope to cover a handoff doc would be exactly the silent scope expansion that gate exists to stop). **The stale text**, §2b "Resume points, per lane": *"Emitter (`ab8055b`) — only remaining step is an in-suite regression pin for defect 4 (scenario `RPL9`: `chmod 500` the ledger dir → assert WARN + `replay=?`). A working probe is at `scratchpad/prove-d4-red.sh`; no re-derivation needed. Suite 120p/1f."* **Three corrections, all PROVEN 2026-08-01 on the Windows machine:** (1) **DONE** — the transport commit for `f018623`+`ab8055b` added `RPL9`-`RPL9g` (8 executing assertions) and the suite is **131/0**, not 120p/1f; that lane has no remaining step. (2) **`scratchpad/prove-d4-red.sh` DOES NOT EXIST here** — it was Mac-local and did not come across, so "no re-derivation needed" is false and the probe *was* re-derived from the code; anyone following the brief literally will hunt for a missing file. (3) **`chmod 500` IS THE WRONG TRIGGER ON THIS TARGET** — MSYS/Git-Bash `chmod` does not produce a write-denying ACL, so the append SUCCEEDS and a permissions-based probe passes **vacuously** (a false GREEN, the worst outcome for a regression pin). The portable trigger, which is what `RPL9` actually uses, is to pre-create the ledger PATH as a **directory**: `>>` to a directory fails on every POSIX shell and on Git-Bash (`Is a directory`, rc=1) and `[[ -f ]]` is false for it, so the code takes exactly the branch a missing file takes. Also worth folding in when that file is next touched: §4's live-hook hash claim is Mac-scoped (see `ROADMAP-FALSE-ETERNAL-RUNNING-01`'s 2026-08-01 correction — the live hook on THIS machine is byte-identical to master, i.e. unfixed).
- **PATH-EQUIVALENCE-CLASS-01 — harness path predicates decide membership case-SENSITIVELY while the delivery filesystem is case-INSENSITIVE; `rrg_in_surface` is fixed, `local-edit-gate.sh` is the named live sibling** (added 2026-07-30 closing harness-reviewer CRITICAL round 5 on `review-record-push-gate.sh`; label: `harness-gap`, `priority:high`). **PROVEN, end-to-end against a real bare remote with `git-hooks/pre-push` installed as the actual pre-push hook:** `git update-index --add --cacheinfo 100755,<blob>,adapters/claude-code/Hooks/injected.sh` (capital H) + commit + push returned **rc=0, gate SILENT, and the path LANDED on the remote**; `git clone` + `git checkout master` then materialised it at `adapters/claude-code/hooks/injected.sh` mode 755 — inside the real carrier directory, beside `review-record-push-gate.sh` itself. `--cacheinfo` is what makes it reachable: it writes the index entry directly, so the capital-H path never has to survive a case-insensitive working tree. **THE CLASS:** a membership predicate that decides from a path STRING must normalise on every equivalence the DELIVERY LAYER collapses; if its equivalence relation is narrower, every string in the gap is a silent hole. Same class as round 4's CRITICAL 2 (predicate asked about git's C-quoted *rendering* rather than the path) — there the gap was enumerator→predicate, here it is predicate→checkout. **MEASURED on this APFS volume** (two byte-distinct names created; did the second overwrite the first): ASCII case COLLAPSED · Unicode case COLLAPSED · U+017F long-s→s COLLAPSED · U+212A Kelvin→k COLLAPSED · NFC vs NFD COLLAPSED · trailing dot DISTINCT · trailing space DISTINCT. **FIXED in that commit — `hooks/lib/review-record-gate-lib.sh`'s `rrg_in_surface`** (fold before the surface test; exact-path exemptions stay case-SENSITIVE so an exemption cannot be widened by case). All 13 surface arms were broken identically, not just the 5 reported. The three consumers of that predicate — `hooks/review-record-push-gate.sh`, `hooks/review-record-commit-gate.sh`, `hooks/lib/review-queue-auto-enqueue-lib.sh` — call `rrg_in_surface` and carry no independent path arms, so they inherit the fix. **NOT FIXED — the one live sibling, named rather than dropped: `hooks/local-edit-gate.sh:101-114` (`is_under_claude_local`).** HYPOTHESIZED (from a read-only sweep of `hooks/`, `scripts/`, `git-hooks/`; NOT yet reproduced end-to-end — that is the next step): its `case "$normalized" in "$normalized_local"/*|"$normalized_local")` arms normalise Windows separators and double slashes but not case, so `~/.claude/Local/CLAUDE.md` would answer "not under ~/.claude/local", and the gate (`manifest.json` entry `local-edit-authorization`, `blocking: true`, PreToolUse on Edit|Write|MultiEdit) would allow the write with no `/grant-local-edit` marker while APFS materialises it at the real path. **REFUTED BY:** running the gate against a capital-L path and observing it still block. Fix shape: fold both `$normalized` and `$normalized_local` before the glob. **Audited and SAFE (no action) — 41 further callsites**, all either exemption/exclusion arms where a case-variant miss yields MORE scrutiny (`harness-hygiene-scan.sh:689-879`, `scope-enforcement-gate.sh:165-195`, `concurrent-ownership-gate.sh:1048`) or non-enforcing classification/routing (`doctrine-jit.sh:188,259`, `backlog-plan-atomicity.sh:190,210`, `vaporware-volume-gate.sh:283,290,309`, `decisions-index-gate.sh:205`, `env-local-protection.sh:219`, `work-integrity-gate.sh:998`). **Re-derive:** `rg -n 'case "\$(rel|full|path|p|f)" in' adapters/claude-code/hooks/ adapters/claude-code/scripts/ adapters/claude-code/git-hooks/ | rg -v 'casefold|nocasematch|tr .A-Z..a-z.'`. **Standing rule** (extends GIT-PATH-QUOTING-CLASS-01's): every harness consumer of git path output must disable quoting AND use NUL separation **AND normalise to the delivery filesystem's equivalence class before the predicate decides membership**. Trailing dot/space (a Windows-checkout equivalence) stays open and untestable here — no Windows checkout of this repo exists.

- **DOCTOR-DEBT-SNAPSHOT-20260801-01 — post-integration full doctor: 87 red / 55 warn, decomposed; each class routed** (added 2026-08-01; label: `harness-hygiene`, `priority:medium`; fold-in: the lanes named per class). Breakdown: 81× budget-worktrees-branches (57 worktrees vs ≤6 — the purge lane; purge-verified-20260729.sh is the operator-authorized per-row-reverifying tool); budget-active-plans 23 vs ≤3 (F.3 dispositions lane — operator did 3 on 2026-07-31); obs-ask-capture-completeness 13/14 sessions unregistered (workstreams-read ask-capture splice — own lane); budget-blocking-gates **15/14 — the +1 is the merged attribution gate, so the operator's pending KEEP/VETO decision (NY-1785556662-b3bd) RESOLVES this row either way** (VETO→demote→14; KEEP→consolidate per ADR 059 D7); obs-scheduled-tasks: janitor transient (reboot window, self-healed to 267009-running), session-resumer Disabled-by-recorded-defer (false-fire class, nl-issue filed 2026-08-01); legacy-paths health-tick.sh FIXED same day (config-driven sweep root). NOT new debt — a routing snapshot so the next doctor reader does not re-triage from scratch.

- **GIT-PATH-QUOTING-CLASS-01 — 30 harness consumers feed `git`'s C-QUOTED path rendering straight into a path predicate; the review-surface three are fixed, the rest are audited-not-fixed** (added 2026-07-30 closing harness-reviewer CRITICAL 2 round 4 on `review-record-push-gate.sh`; label: `harness-gap`, `priority:high`). **PROVEN, end-to-end against a real bare remote with the live gate as the real pre-push hook:** a brand-new `adapters/claude-code/hooks/pré-push-gate.sh` pushed **rc=0, gate SILENT, file ON the remote** as `"adapters/claude-code/hooks/pr\303\251-push-gate.sh"`. `git diff --name-only` does not emit paths — it emits a RENDERING, and under git's default `core.quotePath=true` a non-ASCII byte or a backslash makes that rendering a C-quoted string. `rrg_in_surface` (correct in itself) answers OUT for the quoted form and IN for the raw path: **the predicate was right and the CALLER was wrong.** Measured, so the fix is not guessed: plain `--name-only` quotes non-ASCII AND backslash; `-c core.quotePath=false` alone STILL quotes backslash; `-z` alone yields raw; **both tokens together** is the safe form, consumed with `while IFS= read -r -d ''` (verified on `/bin/bash` 3.2.57: 3/3 records). A SPACE is never quoted, which is exactly why the obvious "weird filename" probe never found this. **FIXED in that commit — the three consumers that feed the review-surface predicate:** `hooks/review-record-push-gate.sh` (all production enumerations, via `_rrpg_diff_z`/`_rrpg_diff_raw_z` which bake both tokens in so a future call site cannot forget one), `hooks/review-record-commit-gate.sh:428`, `hooks/lib/review-queue-auto-enqueue-lib.sh:100`. **NOT FIXED — the remaining 27, enumerated here rather than left as "audit the class someday".** Highest-value first: **`hooks/pre-push-scan.sh:218`** (`files=$(git diff --name-only "$range")` — the CREDENTIAL scanner; a C-quoted path is a file whose contents are never scanned for secrets, i.e. the same shape as this finding but on the security scanner, and it is the one to fix next). Then: `hooks/scope-enforcement-gate.sh:1681`, `hooks/findings-ledger-schema-gate.sh:564`, `hooks/definition-on-first-use-gate.sh:457`, `hooks/evidence-before-fix-gate.sh:639`, `hooks/harness-claim-lint.sh:322`, `hooks/pre-commit-tdd-gate.sh:217,231,289`, `hooks/no-test-skip-gate.sh:47`, `hooks/observed-errors-gate.sh:136`, `hooks/migration-naming-gate.sh:153`, `hooks/claude-md-hygiene-gate.sh:334`, `hooks/wire-check-gate.sh:866`, `hooks/work-integrity-gate.sh:822`, `hooks/bug-persistence-gate.sh:540,550`, `hooks/find-scan-warn.sh:50`, `scripts/static-trace.sh:326,343`, `scripts/review-runner.sh:310,359`, `scripts/end-manifest.sh:208,513`, `scripts/coord-pull.sh:102`. **Already correct (no action):** `hooks/harness-hygiene-scan.sh:963,972`, `hooks/harness-doctor.sh:2662`, `hooks/review-finding-fix-gate.sh:228`, `hooks/decisions-index-gate.sh`, `hooks/pre-commit-gate.sh:158`. **Why not fixed here:** the dispatched scope was the review-record gate family; rewriting 27 unrelated gates' enumeration + consumption loops (each needs a temp file, since NUL cannot survive command substitution) is a separate sweep with its own FP surface per gate. **Re-derive the list:** `bash` the audit in the round-4 evidence section of `docs/plans/review-gate-identity-anchor-2026-07-30.md`, or `grep -rnE 'git .*(diff --name-only|diff --cached --name-only|ls-files)' adapters/claude-code/hooks/ adapters/claude-code/scripts/ | grep -v -- '-z'`. **Standing rule now in doctrine** (`doctrine/review-before-deploy.md`, "Subject-set enumeration", rule 3): every harness consumer of git path output that feeds a path predicate must disable quoting AND use NUL separation.

- **HARNESS-DISPATCHER-MODE-01 — `adapters/claude-code/git-hooks/post-commit` is tracked `100644` at master, so git silently refuses to run it in every clone** (added 2026-07-30 while closing harness-reviewer CRITICAL 3 round 4; label: `harness-gap`, `priority:high`). **PROVEN:** `git ls-tree master adapters/claude-code/git-hooks/` returns `100644 … post-commit` against `100755` for `pre-commit`, `pre-merge-commit`, `pre-push`, `pre-push-pr-template.sh`. Git checks the executable bit before running a hook and skips a non-executable one with only an `advice.ignoredHook` hint, so this dispatcher has not fired for anyone whose checkout carries that mode. This is the LIVE instance of the class CRITICAL 3 named (the repo has been bitten twice before — HARNESS-GAP-65 and the 2026-07-14 I3 incident). **Directly related, and CLOSED in that commit:** `review-record-push-gate.sh` now enumerates file MODE on a `git diff --raw` arm and treats any transition on an in-surface path as UNCOVERED, so a `git update-index --chmod=-x` of a dispatcher is BLOCKED at push time (self-test Scenario 17g, mutation-proven by 21d). What is NOT closed is the working-tree `chmod -x` variant — git runs no hook at all for that push, so no control inside the hook chain is reached; enumerated as `manifest.json` `review-record-push-gate.bypass_paths[14](c2)` with its impossibility argument. **Not fixed here** because flipping the mode ARMS a hook that has not run in its current form — a behaviour change needing its own verification (what does `post-commit` do, does it still do the right thing, what fires when it starts running?), not a side effect of a review-gate fix. **Fix (future session):** (a) read `git-hooks/post-commit` and establish whether it should still run at all (Chesterton's Fence — it may have been deliberately disarmed by mode at some point, in which case say so IN the file); (b) if yes, `git update-index --chmod=+x adapters/claude-code/git-hooks/post-commit` and verify what it does on a real commit before pushing; (c) consider a `harness-doctor.sh` check that REDs when any tracked `git-hooks/<dispatcher>` lacks the executable bit — golden scenario = this entry; expected FP rate = 0 (a dispatcher is either meant to run or should not be in that directory); retirement condition = the dispatchers move out of the working tree into a location the pusher cannot rewrite. Note (c) would RED immediately on `post-commit`, which is why it belongs with (a)/(b) and not before them.
- **SCOPE-GATE-HEADER-CLAIMS-INTERSECTION-IMPLEMENTS-UNION-01 — three defects in `scope-enforcement-gate.sh`, fix BUILT and COMMITTED IN A BUILDER WORKTREE, not yet on any shared branch; residuals recorded here** (added 2026-07-30; label: `harness-gap`, `priority:medium`). **Status:** LANDED on master 2026-08-01 — the fix (amended to `dfc9f75` on `worktree-agent-a2605766de68f6102`) was cherry-picked by the takeover session; suite + review + record gated the push — resolve any claim about what those branches contain with `git log <branch> -- <path>`, never against a worktree HEAD (the `worktree-base-reported-as-branch-state` class recorded under REVIEW-RECORD-GATE-STAGE-AND-COMMIT-FAIL-OPEN-01 below). All three were reproduced by EXECUTION before any edit, and each carries a mutation-proven self-test scenario (suite 40/0 of 38 → **47/0 of 42**, identical on `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15).
  **D1 — header documented INTERSECTION, code implemented UNION** (header ~:105-107 vs the `reject_count -eq NUM_PLANS` test ~:2035). PROVEN by execution: two active plans, A claiming `src/alpha/module-one.ts` and B claiming `src/beta/module-two.ts`, staging only A's file → **rc=0** (union). **Resolved in favour of the CODE — union is correct, the comment was the defect.** Reasons, now written into the file's header: (a) plans are independent concurrent workstreams and this repo routinely carries ~20 ACTIVE at once, so under intersection a file would have to be declared by ALL of them and essentially every commit would block — intersection is not merely stricter, at N>1 it is degenerate; (b) intersection would falsify the gate's OWN option-2 remedy ("open a new plan listing the staged files and re-commit"), which provably cannot work if the other active plans must also claim the file — the same remedy-chain defect already recorded for review records in `_is_system_managed_path`; (c) union is the pre-existing tested oracle — self-test scenario 12 has asserted "in scope iff at least one active plan claims it" since the gate was written. Scope discipline is preserved because the union is over DECLARED scopes: every in-scope file is still named by some plan.
  **D2 — the scope parser read BULLETS ONLY, so a markdown-TABLE `## Files to Modify/Create` section declared zero paths.** Now parses table rows as first-class scope declarations. **Attribution defect fixed alongside it:** a plan whose scope section yields nothing gets `__STRUCTURAL__` and therefore rejects every staged file, and it used to be printed on the SAME "Rejected by plan(s)" line as plans that genuinely evaluated the path — so with one broken plan and one healthy one the message named BOTH, sending the reader to edit the innocent plan. The two causes are now separate lists with separate wording ("Rejected by plan(s)" vs "NOT judged on scope by plan(s) … they did not evaluate this file at all"), and the zero-paths case is LOUD by name ("declares a … section that yields NO paths" + "Effect: a plan that declares no paths rejects EVERY staged file").
  **D3 — NEW, found by execution while probing D1/D2: the `RAWLEN < 20` emptiness heuristic ran BEFORE the parsed-entry check**, so a section that was SHORT BUT VALID (`- \`a/b.ts\`` — 18 non-whitespace chars, one perfectly good path) blocked an in-scope commit and told the author the plan was "empty / placeholder-only" — naming a defect the plan did not have. Successfully-parsed entries now outrank the byte-count proxy; RAWLEN is consulted only to explain WHY a zero-path section is empty.
  **BLAST RADIUS — measured by executing the gate's real parser over every plan (`docs/plans/` and `docs/plans/archive/`), section-scoped to `## Files to Modify/Create` alone: ZERO plans use a table today.** Top level: 54 files, 20 ACTIVE, 21 yield paths, **0 table-form, 0 zero-path**, 33 with no such section — all of them `*-evidence*.md` sidecars and **none ACTIVE**. Archive: 242 files, **0 table-form**, 4 zero-path (bullet-form but prose/placeholder-only), 78 no section. So D2 was a LATENT defect with no current instance — the table parser prevents a future incident rather than curing a present one. **How the gate treats a missing section:** `NO_SCOPE_SECTION` → `__STRUCTURAL__` → that plan rejects everything and the commit blocks; harmless today only because no ACTIVE plan lacks the section, and a single ACTIVE plan acquiring one would block every commit repo-wide until fixed.
  **Residual 1 (deliberate, documented in-file):** table parsing scans ALL cells of a row, not just the first, so a description cell that backticks another real path contributes it to the plan's scope. This matches the established bullet behaviour (§D.0.7 already loops every backtick pair on a bullet including its trailing prose), and for a blocking gate the widening direction is the safe one — it can only allow a commit the plan's own text names, never block one it declares. Revisit only if a plan is observed gaining scope it did not intend.
  **Residual 2 (unreproduced, do not act without more data):** one run of `hooks/lib/git-command-parse.sh --self-test` under `/opt/homebrew/bin/bash` 5.3.15 reported `114 passed, 1 failed` with no FAIL line in the captured output; 6 immediate re-runs on 5.3 and 6 on 3.2 all returned `115 passed, 0 failed`, and the cross-gate agreement check reported `28/28 commands resolve identically` every time. HYPOTHESIZED transient (the suite forks ~11760 fixture combinations, so a transient fork/temp-dir failure is plausible); REFUTED by any reproduction with a named failing scenario. Unrelated to this change by construction — `git diff --stat` for the fix touches `scope-enforcement-gate.sh` only, and no commit-target-resolution code was modified.

- **COCKPIT-ASKS-ENDPOINT-DOWN-ANTINOISE-DENYLIST-01 — `GET /api/asks` and `GET /api/ask/<id>` are returning `ok:false` on the LIVE cockpit right now, so the entire ask-tree pane renders its error state for the operator** (added 2026-07-30 while sweeping COCKPIT-DEAD-FILE-HREF-RESIDUAL-01; label: `product-bug`, `priority:high`). PROVEN, live at `127.0.0.1:7733` AND reproduced on a clean instance from this worktree at `:7744`: `curl -s http://127.0.0.1:7733/api/asks` returns `{"ok":false,"error":"payload schema validation failed","diagnostics":["gate/hook identifier leaked at $.groups[1].asks[0].summary (matched /\\b(plan-lifecycle|workstreams-emit|…)\\b/i): \"Take a look at <task-notification> handling in workstreams-read.\"", …]}`, and `GET /api/ask/ask-auto-4001cc513f6957da` fails the same way at `$.summary` and `$.narrative[0].summary`. **Root cause (PROVEN):** `server/payload-schema.js`'s `GATE_HOOK_DENYLIST_PATTERNS` anti-noise scan is fail-closed for the WHOLE payload, and a real operator ask's own `summary` legitimately names a mechanism (`workstreams-read`) because that mechanism *is what the operator was asking about*. The denylist cannot distinguish "UI copy that leaked an internal identifier" (what it exists to stop) from "operator prose whose subject matter IS the identifier". **This is the exact failure shape the 2026-07-19 respec already fixed once for `/api/todo`** — see `server.js`'s own header comment there: *"a fail-closed 500 here nuked the ENTIRE list because one item mentioned a .ps1 path (live operator-visible outage)… Availability outranks lint"* — the same reasoning was never applied to the asks payload. **Not fixed here** (out of scope: this round's dispatch was the dead-`file://`-href class sweep; changing the anti-noise fail-closed policy is a deliberate constraint-1 decision that needs its own scope call, and the `description` field already carries a documented `DENYLIST_EXEMPT_KEYS` precedent for exactly this "the identifier is the subject matter" argument). **Note this MASKS part of the dead-href fix's live visibility:** the asks pane's cured links cannot be seen live until this is resolved (they were instead proven by executing the real shipped `asks.js` in a real browser DOM against a stubbed-valid payload). **Candidate fixes:** (a) extend `DENYLIST_EXEMPT_KEYS` to `summary`/`narrative_excerpt` with the same compensating length cap `description` uses; (b) apply the `/api/todo` respec verbatim — flag the offending item (`noise_flag`) and render it anyway, rather than failing the whole payload; (c) scope the scan to hardcoded client copy only and drop it from server-prepared operator prose entirely. (b) matches the established precedent and the constitution's availability-outranks-lint principle.
- **SCOPE-GATE-HEADER-CLAIMS-INTERSECTION-IMPLEMENTS-UNION-01 — `scope-enforcement-gate.sh`'s header documents multi-plan scope as INTERSECTION while the code implements UNION; and its files-to-modify parser silently ignores markdown TABLES** (added 2026-07-30 while building `docs/designs/code-trace-methodology.md`; label: `harness-gap`, `priority:medium`). Two independent defects in the same gate, both found by that document's own Move 9 (claim-vs-measurement on a stated contract) after the gate blocked this session's commit. **(a) Doc/code divergence, PROVEN by reading both:** the header at `adapters/claude-code/hooks/scope-enforcement-gate.sh:104-107` states *"Multiple active plans: Required behavior is intersection — a file in scope of plan A but not plan B is out of scope."* The implementation at `:2035` is `if [[ "$reject_count" -eq "$NUM_PLANS" ]]` — a staged file is out-of-scope only when **every** active plan rejects it, i.e. UNION (in scope of ANY plan ⟹ allowed). With 21 active plans the documented semantics would block essentially every commit; the implemented semantics are the sane ones, so **the code is right and the header is wrong**. Anyone reasoning from the header will mis-predict the gate. **(b) Table-format blind spot, PROVEN by direct repro:** the parser (contract at `:89-97`) extracts paths only from bullet lines (`- ` / `* `). A `## Files to Modify/Create` section written as a markdown table — the shape `~/.claude/templates/plan-template.md` itself renders in several places, and the shape this session's plan was first written in — yields ZERO declared paths, so the plan silently declares nothing and the gate rejects every file in it. The failure is silent: no "your plan declares no files" warning, just an out-of-scope block naming all 21 plans, which points the reader at the wrong cause entirely. Reproduced twice this session (table → rejected; identical content as bullets → allowed). **Fix:** (a) correct the header to say union and state the rationale (a file governed by any active plan is in scope); (b) either teach the parser to read table rows (first cell, backtick-stripped) or make an empty declared-path set an explicit, named error — "plan `<slug>` declares no files under `## Files to Modify/Create` (bullets only; tables are not parsed)" — so the silent-zero case can never masquerade as a scope violation. (b) is the load-bearing half: a silent parse-to-empty in a blocking gate is the same fail-silent class this repo has been sweeping all week.

- **COCKPIT-DEAD-FILE-HREF-RESIDUAL-01 — `asks.js` and `backlog.js` STILL emit `file://` anchors from the http-served cockpit page; only `roadmap.js` (Round 15) and `inbox.js` (Round 17) were ever cured** (added 2026-07-30 while building `docs/designs/code-trace-methodology.md`; label: `product-bug`, `priority:medium`). This is the SAME class the ledger closed twice — row 70 ("plan links don't work") and row 87 ("the links on the Inbox tab don't work") — surviving in two more panes. **PROVEN by execution, not by reading**: extracting the real `toFileUrl`/`absoluteLinkHref`/`isAbsoluteHref` bodies from the working tree at `366a88b` and running them over four representative inputs emitted **6 `file://` anchors** (`node` harness, output retained in the design doc's Defect-6 row). **Call-graph reachability confirmed, both sites reach a real DOM `href`:** (a) `neural-lace/workstreams-ui/web/asks.js:94-100` `toFileUrl` -> `:122-128` `absoluteLinkNode` sets `fa.href = fileUrl` on a clickable `<a>`, reached from FOUR callsites — `:484` (`item.raw_link` recovery row), `:506` (`item.links[]`), `:573` (`t.evidence_link`), `:732` (`detail.verbatim_ref`); (b) `neural-lace/workstreams-ui/web/backlog.js:45-56` `toFileUrl`/`absoluteLinkHref` -> `:484-492` sets `openLink.href = fileHref` on an `<a target="_blank">` labelled "open backlog.md". **Why these are dead:** the page is served over `http://127.0.0.1:7733` (the `local.neurallace.workstreams-cockpit` LaunchAgent sets `CTREE_PORT=7733`), and a browser silently blocks `file://` navigation from an `http` document — the fact the repo ALREADY recorded in `web/roadmap.js:1014` ("the OLD `file:///` href was a DEAD link from this http-served page (confirmed live at :7733 — no navigation, no network activity on click)") and in `web/app.css:613,1892`. **Not fixed here** (this session's scope was the trace-methodology design doc, not a cockpit build). **Fix:** route both through the in-page doc modal exactly as row 70/87 did — `/api/doc {project,path}` + the shared md-render + `docModal` — never a second renderer; keep the existing copy-path affordance as the fallback for paths outside every configured project root. **Detection note (why this matters beyond the two files):** ONE command finds the whole class and would have found it at either prior fix — `git grep -n "file://" -- neural-lace/workstreams-ui/web`. Both prior fixes cured the reported pane and left the siblings; a class-wide sweep at fix time is the cheap generalization. Cross-ref: `docs/reviews/cockpit-ui-requirements-ledger.md` rows 70 and 87; `docs/designs/code-trace-methodology.md` Defect 6 + Move 1 (producer/consumer scan).

- **DETERMINISTIC-PROCESS-PROOF-OBLIGATION-UNWIRED-01 — `deterministic-process.md` mandates `chokepoint` + `bypass_paths` on every blocking manifest unit, but `manifest.schema.json` FORBIDS both keys and 0 of 40 blocking units carry them** (added 2026-07-30 while building the Intended-Functionality gate; label: `harness-gap`, `priority:high`). PROVEN, three independent observations: (1) `adapters/claude-code/doctrine/deterministic-process.md` §"The proof obligation" states *"Every `\"blocking\": true` manifest unit declares: `chokepoint` … `bypass_paths` …"* and its header claims *"`harness-doctor.sh` REDs on one declaring neither"*; (2) `python3 -c` over `manifest.json` returns `chokepoint: []` and `bypass_paths: []` across all 149 pre-existing entries, of which **40** are `blocking: true`; (3) adding those two keys to a new entry makes `manifest-check.sh` emit `RED schema: unknown key 'chokepoint' (additionalProperties: false)` and the same for `bypass_paths` — i.e. the schema actively rejects compliance with the doctrine. **This is precisely the constitution §10 "theatre" defect the same doctrine file names** ("documented enforcement that does not fire … wire it or delete the claim"): the proof obligation is documented, unsatisfiable, and unchecked. The doctrine landed 2026-07-30 in commit `e91cdfa`, one commit before this was found. **Not fixed here** — the correct fix touches `manifest.schema.json` plus a backfill decision across all 40 blocking units, which is an operator/orchestrator-owned scope call, not a side effect of an unrelated build. **Workaround used by the new `intended-functionality-if-statement` entry (so no information is lost):** its chokepoint and its four enumerated bypass paths are written inline into `honest_status`, with a note naming this contradiction. **Fix (future session):** (a) add `chokepoint` (string) and `bypass_paths` (array of strings) as optional properties to `adapters/claude-code/schemas/manifest.schema.json`; (b) decide whether the doctor's claimed RED is built now or the claim is softened until the 40-unit backfill lands — per §10 the claim must not outlive the mechanism; (c) backfill the 40 blocking units, or scope the requirement to `added_after >= 2026-07` and say so in the doctrine.
- **REVIEW-RECORD-GATE-STAGE-AND-COMMIT-FAIL-OPEN-01 — `review-record-commit-gate.sh` silently fails open when `git add` and `git commit` are ONE compound command** (found 2026-07-30 while committing the ROADMAP-FALSE-ETERNAL-RUNNING-01 second pass; label: `harness-gap`, `priority:high`, constitution §10 theater). **PROVEN by executed trace, all three runs against the same worktree changes:** with the files STAGED, `{"command":"git commit -m x"}` → **exit 2 (BLOCKED)** and `{"command":"git add -A && git status --short && git commit -F …"}` → **exit 2 (BLOCKED)**; with the IDENTICAL changes left UNSTAGED, that same compound command → **exit 0, zero output**. Cause: the gate resolves staged-file coverage by reading the git INDEX at PreToolUse time — which is *before* the `git add` in the very command it is judging has run — so it sees an empty index, matches its own documented bailout #1 ("No staged in-surface file → silent allow, the common case"), and allows. **Consequence, live:** commit `d0430ca` landed `adapters/claude-code/hooks/workstreams-emit.sh` (an in-surface file; new blob `62a6346d…`, NOT the blob `e36a925d…` that `docs/reviews/records/grandfather-manifest.json` pins for that path, and covered by no PASS record in `docs/reviews/records/`) with **no review record and no block** — exactly the state the gate exists to prevent. This is not a bypass-env story: no `REVIEW_RECORD_GATE_OVERRIDE` was set and none was needed. **Severity reasoning:** `git add -A && git commit` is an extremely common single-call shape (it is what the agent above used unprompted), so the gate's real-world coverage is far below its documented coverage — and the failure is SILENT, so nobody learns it happened. **Candidate fixes:** (a) when the command itself stages (`git add …`, `git commit -a/-A`), resolve coverage against the WORKING TREE rather than the index — the gate's own "bailouts resolve toward BLOCK" principle already argues for this; (b) failing that, detect a staging verb in the same command string and resolve toward BLOCK with a message telling the operator to stage first and re-run; (c) add a self-test scenario for the unstaged-compound shape — the existing suite covers command-position parsing (Scenarios 14/21) but never varies INDEX state, which is why this was invisible. **Composes with:** the gate's existing NL-FINDING-016 remedy-chain note (a fix and its retry are never one compound command) — the same one-call habit that note accommodates is what defeats the gate here.
  **SCOPE CORRECTION (same day, before this entry was acted on — the finding is real but NARROWER than first written).** A JIT doctrine injection surfaced **Amendment H (2026-07-30, `deterministic-process.md`)**, which already demotes `review-record-commit-gate.sh` to **ADVISORY** and moves authority to a new `hooks/review-record-push-gate.sh` wired into `git-hooks/pre-push`, reading coverage **at the COMMITTED blob**. A push-time check over committed blobs is **structurally immune to this fail-open** — there is no index-vs-worktree timing window at push time — so Amendment H closes the class by architecture, not by patching the parser. **Therefore: do NOT spend effort fixing the commit gate's index timing.** What remains true and worth acting on: **`origin/master` (`17c0d4c`) has neither** — verified `git cat-file -e origin/master:adapters/claude-code/hooks/review-record-push-gate.sh` → *does not exist* — so on the merge target the commit gate is still documented-BLOCKING and still fails open exactly as measured, and **the fail-open window persists for anyone on master until Amendment H lands there.**
  **DRIFT CLAIM RETRACTED (round 3).** An earlier revision of this entry said "this branch and `origin/master` contain NEITHER" and called the live harness "AHEAD of origin/master … drift worth a look". **That was FALSE and the operator was told it.** The BRANCH `wip/harness-hardening-2026-07-29` (tip `366a88b`) has had BOTH since **`3a6e821`, authored 2026-07-30 17:03:00** — verified `git log --diff-filter=A wip/harness-hardening-2026-07-29 -- …push-gate.sh`, and its commit gate carries 9× ADVISORY. That is ~40 minutes BEFORE the sentence was written. Live `~/.claude/` installs from the branch, so live-having-them is **ordinary in-flight state, not out-of-band drift** — there is nothing to investigate.
  **Root cause of MY error, recorded because it generalizes:** I resolved a claim about *the branch* against *my detached worktree's base* (`17c0d4c`), which is merely where this worktree was cut from and says nothing about where the branch has moved since. **Class: worktree-base-reported-as-branch-state. Standing rule: any claim about what a branch or a merge target contains resolves against `git rev-parse <branch>` / `git cat-file -e <branch>:<path>` / `git log <branch> -- <path>` — NEVER against the current worktree's HEAD or base.** Class for the ledger is unchanged and still worth recording: *a blocking gate whose precondition is evaluated before the command that establishes it*.

- **ESTATE-T9-EVIDENCE-POINTERS-NOISE-01 — close-plan.sh's T9 "Evidence pointers" derivation inherits generate_completion_report's pre-existing high-churn-file noise** (added 2026-07-30 from accountable-estate T9's live acceptance demonstration; label: `harness-gap`, `priority:low`). T9's `generate_closure_outcome_section` deliberately reuses `generate_completion_report`'s EXISTING files-to-modify -> `git log --oneline --no-merges -- <path>` derivation ("one implementation, not two"), but that derivation was already noisy for any plan whose `## Files to Modify/Create` names a high-churn shared file (e.g. `docs/backlog.md`, touched by thousands of unrelated commits repo-wide) — observed live closing `context-watermark-opus5-window.md` for real: its "Evidence pointers" section filled with `sort -u`-ordered (effectively SHA-random, not date-ordered) commits spanning the WHOLE repo's history, none related to that plan's actual W1-W3 work. This is a PRE-EXISTING characteristic (the Completion Report's own "Commits referencing these files" section has the identical noise, confirmed by inspecting the same archived plan), not a T9 regression — T9 inherited it by design (shared derivation) rather than building a second, competing one. **Not fixed here** (T9's own scope discipline: reuse the existing derivation, don't fork a second evidence-pointer algorithm mid-task). **Candidate fixes for a future session:** (a) bound `git log` to commits between the plan's own first-commit and close timestamps (`--since`/`--until`), which would exclude the vast majority of a shared file's unrelated history; (b) exclude known always-touched shared files (`docs/backlog.md`, `SCRATCHPAD.md`, `NEEDS-YOU.md`) from the evidence-pointer file list specifically, while still listing them in the Completion Report's own file list; (c) cap by commit-message keyword/slug relevance rather than a bare `head -N`. **Composes with:** any future rework of `generate_completion_report` itself, since fixing the shared derivation fixes both consumers at once.

- **HARNESS-GAP-57 — anti-vaporware config-control policy doesn't cover the INVERSE shape: a consumed lever with zero producers** (added 2026-07-29 from accountable-estate T7 D-4's live counter-example; label: `harness-gap`, `priority:high`; **disposition: COMPLETED 2026-07-30 → `docs/plans/archive/anti-vaporware-config-controls-generalization.md` (single-task plan, opened per scope-enforcement-gate's own "genuinely separate work gets its own plan" remediation path since 16 unrelated plans were ACTIVE on this branch; task-verifier PASS conf 9 at commit a40da18, reproduced the mutation transcript itself; closed + archived via close-plan.sh at commit 51757e8)**). **Context.** HARNESS-GAP-45 (closed 2026-07-13 via `docs/plans/archive/vaporware-config-controls.md`, 8/8 task-verifier PASS) named the "decorative config control" vaporware class and built its enforcement: the registry-vs-callsite invariant (`doctrine/vaporware-prevention-full.md`), functionality-verifier's config-control protocol, and functionality-auditor's registry-vs-callsite sweep. That enforcement checks ONE direction — does a registry entry (permission ID, feature flag with a UI) have an enforce-mode CONSUMER — and structurally assumes the other half (the producer) is guaranteed, because a UI toggle's producer is the user clicking it. **The gap.** Non-UI config levers — env vars, CLI overrides, caller-set fields read deep in library code — have no such guarantee. `NL_PROTECTED_ORCHESTRATOR`, documented in `hooks/lib/admission-lib.sh` as the tag a "protected downstream orchestrator" must set, was discovered (accountable-estate T7, task-verifier pass 4, D-4, 2026-07-29) to have ZERO producers anywhere in the repo — all 888 live ledger rows carry `protected:0`. It IS consumed (real read site, real branch); nothing ever sets it. Neither functionality-auditor's sweep (no registry+UI surface here) nor functionality-verifier's config-control protocol (no `Verification: full` task ever claimed this flag governs behavior) would have caught it — a task-verifier pass caught it only by reading the comment narratively, and hand-wrote the honest-status annotation now sitting in the file. Nothing made that catch mechanical or repeatable. **What was built.** (1) `scripts/config-control-producer-scan.sh` — a standing, self-testing, bash-3.2-compatible scan (both `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15 verified) that classifies every consumed `NL_*`-prefixed lever under `hooks/`+`scripts/` as PRODUCED (real standalone assignment exists) / MARKED (no producer, but an honest-status marker sits within a small line-proximity of ANY mention of the var — anchored on mention, not the syntactic read site, because the real admission-lib.sh annotation sits 566 lines from the functional read and 1 line from the var's own name) / ALLOWLISTED (documented external-producer carve-out) / FLAGGED (none of the above — the vaporware shape). 7/7 self-test scenarios pass under both interpreters, including a golden-pre-fix/golden-post-fix pair reproducing the real admission-lib.sh text verbatim (proves the scan keys on the marker, not the var name) and a live-repo scenario asserting zero FLAGGED against the actual current trees. Mutation-tested: deleting the `NL_CHECKOUT_OVERRIDE` allowlist entry flips the live-repo scenario and overall self-test from PASS to a reported FLAGGED + exit 1; restoring the entry returns both interpreters to GREEN. (2) `config/config-control-allowlist.txt` — the documented external-producer carve-out (7 pre-existing legitimate operator-shell/self-test-only overrides audited against their real read sites and recorded with per-entry justification: `NL_CHECKOUT_OVERRIDE`, `NL_CROSS_REPO_TOUCH_OK`, `NL_EXCLUSIONS_VERIFY_TIMEOUT`, `NL_ISSUES_BACKLOG_PATH`, `NL_ISSUE_CLI_OVERRIDE`, `NL_SELFTEST_EXCLUSIONS_FILE`, `NL_SPAWN_PROCESS_COUNT_OVERRIDE`). (3) Doctrine: `doctrine/vaporware-prevention.md` (compact, new "Its inverse" clause, 2914B, under the 3000B cap) + `doctrine/vaporware-prevention-full.md` (new "The inverse shape" section: definition, originating case, mechanical-check description, why-standing-not-blocking rationale, full constitution §10 fields). (4) `docs/failure-modes.md` FM-038 — new "Generalization — the inverse shape" bullet. (5) `adapters/claude-code/manifest.json` — new `config-control-producer-scan` entry (kind: gate, blocking: false, wired_template: false, `added_after: "2026-07"` — full new-gate-evidence-bar per ADR 059 D4: `golden_scenario`/`fp_expectation`/`retirement_condition`/`honesty_rationale`/`honest_status` all populated); `manifest-check.sh` GREEN at 146 entries; `doctrine/INDEX.md` regenerated via `--gen-index`. **Why standing, not a new blocking hook (constitution §10).** D-2 in the archived GAP-45 plan declined a new gate for the registry-vs-callsite class, reasoning the existing functionality-verifier/task-verifier blocking chain was sufficient until a decorative control shipped past it — that recurrence being the trigger for a future gate. `NL_PROTECTED_ORCHESTRATOR` IS that recurrence, but in a shape (no registry+UI surface) D-2 didn't anticipate, so this ships the mechanical, self-testing check first (invocable standalone or in CI) rather than a new blocking PreToolUse hook, consistent with D-2's spirit: prove the false-positive rate in practice before wiring it to block. **§10 fields (also in the manifest entry and doctrine-full section verbatim):** golden scenario = `NL_PROTECTED_ORCHESTRATOR` pre/post-annotation states (both are `--self-test` scenarios); expected FP rate = 0% against the live repo today (7 pre-existing legitimate overrides accounted for via the allowlist, not suppressed); retirement condition = a FLAGGED verdict proven wrong by a producer-shape this scan's regex can't see escalates to either extending the regex or retiring the static approach in favor of HARNESS-GAP-39's runtime audit-log method for the same "wired but never exercised" class. **Follow-ups (not this task's scope, logged for a future session):** wiring the scan into `harness-doctor.sh --quick` or a CI workflow as an actually-blocking check once its FP rate has stood for a review cycle; the scan's `NL_*`-prefix scope could generalize to other config-lever naming conventions if this class recurs outside that prefix. Cross-ref: HARNESS-GAP-45 (the registry-vs-callsite half this generalizes), HARNESS-GAP-39 (the runtime audit-log alternative named in the retirement condition), `docs/plans/archive/vaporware-config-controls.md` D-2/D-3 (the prior decisions this respects and extends).
- **HARNESS-GAP-62 — `plan-edit-validator.sh`'s OWN checkbox-flip `TASK_ID` regex still requires a dotted id (`[A-Z]+\.[0-9]+`), never fixed for the `<Key><TaskId>` fused format the cockpit's `plan-parse` was widened to accept in commit a8b114c** (added 2026-07-30 from status-event-ledger SE4's build; label: `harness-gap`, `priority:high`; **disposition: FIXED 2026-08-04, fix(verify-event) commit series, this worktree** — see the AMENDMENT block below for the full fix: `PEV_TASK_ID_ALT`/`PEV_TASK_ID_BOUNDARY` near the top of `plan-edit-validator.sh` now accept all four measured id shapes (classic dotted, fused letter+digit capped 1-3 letters, bare numeric, digit+letter sub-id from a sibling project's real convention) at all three consult sites, plus a standing SILENCE DETECTOR (`verify-event-audit.sh --recent-silence`, wired into `harness-doctor.sh`) so a future regression of this class self-surfaces instead of requiring another manual sweep. `plan-edit-validator` self-test 32/32 (was 27/0), mutation-tested; `verify-event-audit.sh` self-test 10/10 (was 7/0). HARNESS-GAP-63 (the awk double-print bug named below) remains open, unrelated to this fix, out of scope here as originally scoped.). PROVEN (direct regex test, 2026-07-30): `echo '- [x] SE3 — ...' | grep -oE '\[[xX]\][[:space:]]+[A-Z]+\.[0-9]+(\.[0-9]+)*'` and the same against `'- [x] RI1. ...'` both empty-match (rc=1); the identical pattern against a classic dotted id (`B.1`) matches correctly. Call sites: `adapters/claude-code/hooks/plan-edit-validator.sh` lines ~927, ~933 (the `check_docs_impact_warn` new-task-line detector, WARN-only) and ~1729 (the REAL checkbox-flip `TASK_ID` extraction that GATES authorization — this is the load-bearing one). Because TASK_ID resolves empty, `[[ -n "$TASK_ID" ]] && check_evidence_first ...` short-circuits false and the flip falls through to PLAN EDIT BLOCKED regardless of how much real evidence exists. **Impact: this blocks the operator's own two currently-ACTIVE fused-id plans from ever being closed via the normal task-verifier flow** — `docs/plans/status-event-ledger.md` (SE1-SE10) and `docs/plans/review-independence.md` (RI1-RI4, several of which already have real commits landed — e.g. `feat(review-independence RI3)` — yet all four checkboxes are still `- [ ]` in the plan file, consistent with this bug rather than incomplete work). Discovered incidentally while building SE4's flip-time ledger-emit self-test (had to prove the emit fires on a REAL authorized flip; a fused-id fixture ("SE4.1") reproduced this exact block, so the test fixtures were switched to the currently-supported dotted form ("SE.4.1") to keep SE4's own scope narrow — this entry is the follow-up, not a silent workaround). **Fix (not attempted here, out of SE3/SE4/SE10's scope):** widen all three call sites to accept EITHER the classic dotted form OR a capped fused prefix, mirroring the cockpit's own guard exactly (`[A-Z]{1,3}[0-9]+` requires 1-3 uppercase letters immediately followed by a digit, so 4+-letter acronyms like `WCAG` still never match) — e.g. `[A-Z]+\.[0-9]+(\.[0-9]+)*|[A-Z]{1,3}[0-9]+(\.[0-9]+)*` — plus a discriminating self-test scenario (mirroring a8b114c's own `plan-parse 23/0` proof) asserting `SE3`/`RI1`-style ids now flip AND `WCAG 2.2`-style prose still does not false-match. This doctrine amendment is also recorded in `doctrine/claims.md`'s new "Status vocabulary lock" section (SE10) as the parse-level lesson: a vocabulary convention isn't real until EVERY consumer's grammar accepts it, not just the one it was first proven in.

  **AMENDMENT 2026-08-04 (discovered while extending SE4's flip-verdict event with an evidence pointer + bare plan-slug field, per operator directive "check off the check boxes in two places (plan file and ledger)"):** the gap is WORSE than originally scoped — it also blocks the DOMINANT real convention, bare-numeric ids with no letter prefix at all (`- [x] 1. ...`, `- [x] 7. ...`), used throughout `docs/plans/gated-pipeline-master-2026-08.md` and most other active plans in this repo. PROVEN directly (2026-08-04): a synthetic plan with `- [ ] 1. Do the thing` + a fresh, fully valid prose evidence block (Task ID: 1, Runtime verification: present, Verdict: PASS) fed through the real `plan-edit-validator.sh` as a real `Edit` payload is BLOCKED (`PLAN EDIT BLOCKED`, exit 1) — `TASK_ID` resolves empty against `[A-Z]+\.[0-9]+(\.[0-9]+)*` exactly as the fused-id case does, for the same reason (no letter at all, let alone the fused-prefix shape). The previously-proposed fix (`[A-Z]+\.[0-9]+(\.[0-9]+)*|[A-Z]{1,3}[0-9]+(\.[0-9]+)*`) does NOT cover this case either — neither alternative matches a token with zero letters. **Consequence, also PROVEN:** `$HOME/.claude/state/signal-ledger.jsonl` on this machine carries ZERO `flip-verdict` rows in total, despite SE4 having shipped 2026-07-30 — the flip-time ledger-emit mechanism is real, wired, and mechanically enforced for the id shapes it can parse, but has not fired once in this repo's actual history because the dominant real task-id convention (bare numeric) never reaches it. Confirmed independently by `adapters/claude-code/scripts/verify-event-audit.sh --sweep docs/plans` (built in the same session): **926 currently-checked tasks** across `docs/plans/**/*.md` (active + `archive/` + `deferred/`), **0** with a matching `flip-verdict` event on record. **Fix (still not attempted here, out of this session's scope too — it is authorization-path surgery, high blast radius, deliberately not bundled with an additive ledger-field change):** a true fix needs a THIRD alternative in the regex (or a differently-shaped grammar entirely) for bare numeric/dotted-numeric ids with no letter prefix, e.g. `[0-9]+(\.[0-9]+)*` added to the alternation — plus self-test coverage proving all three shapes (`A.1`, `SE3`, `7`) now authorize and flip while non-id prose (`WCAG 2.2`) still does not false-match. Until this lands, `verify-event-audit.sh`'s reported "no verification event on record" count should be read as "the ledger has not yet been given the chance to record this," not as a claim that these 926 tasks were verified without evidence — the evidence-first checkbox-flip authorization itself (rule 3's own gate, unaffected by any of this) still ran and still required real evidence for every one of them; only the SEPARATE, ADDITIVE ledger-event side-channel is silent.

  **LANDED 2026-08-04 (fix(verify-event) commit series, this worktree).** Id-shape census across `docs/plans` (active + `archive/` + `deferred/`, 2144 checkbox tokens after stripping bold-wrapper/sentence-punctuation noise) plus a sibling project's `docs/plans` elsewhere on this machine (this same global hook also gates that repo — 4445 tokens) grounded a FOUR-alternative regex, not the three originally proposed: bare numeric (`7`/`3.2`, 863 occurrences, the dominant estate convention), fused letter+digit capped 1-3 letters (`T1`/`SE3`/`RI1`/`ORG6`, 210), classic dotted-letter (`A.1`, 176, pre-existing/unchanged), and — found only via the cross-repo sweep, not present in any neural-lace ACTIVE plan — digit+letter sub-id (`0a`/`10e`/`0a.1`, that sibling project's real currently-ACTIVE plan convention, tasks `0a`-`0i`). Deliberately excluded (measured, present, but archive-only or single-occurrence, not in any ACTIVE/DEFERRED plan): bold-wrapped bare numeric (`**1.`, 9 archived files), a bare digit+UPPERCASE reversal (`20R`, 1 archived occurrence), a bare single letter with no digit (`A`, 1 deferred occurrence). A trailing-boundary requirement (`PEV_TASK_ID_BOUNDARY`) prevents the widened bare-numeric/digit-letter alternatives from false-matching an ordinal-word prefix in task prose (`1st` -> `1s`) — confirmed by direct test before the guard existed. Fixed consistently at all three consult sites named above (the authorization extraction; `check_docs_impact_warn`'s WARN-only new-task detector; that function's `--self-test` replica) via one shared `PEV_TASK_ID_ALT` constant. Authorization-vs-emission: NOT an independent asymmetry in this codebase — `emit_flip_ledger_event` is only ever reachable AFTER authorization succeeds (both consult the SAME extracted `TASK_ID` variable), so widening the one shared extraction chokepoint fixes both by construction; no separate "emit even when authorization fails" pathway exists or was built (that would require inventing a new, noisier event type on every rejected edit, out of proportion to this fix). Self-tests: `plan-edit-validator.sh` F28-F32 (one real e2e subprocess flip per new shape + a negative ordinal-word boundary control + the docs-impact-warn consistency fix), 32/32 total (was 27/0); mutation-tested (reverting `PEV_TASK_ID_ALT` to the pre-fix narrow form turns exactly F28/F29/F30/F32 red, F1-F27+F31 stay green). **Class fix (not just the instance):** `verify-event-audit.sh --recent-silence [<root>] [<since>] [<min-flips>]` is a new standing SILENCE DETECTOR — diffs `git log -p` over the window for added checked-checkbox lines against ledger `flip-verdict` events in the same window, WARNs only on TOTAL silence (>= min-flips recent flips AND zero matching events, default 3/7-days) so a future regression of this class self-surfaces instead of requiring another manual `--sweep`. Wired into `harness-doctor.sh` (`check_verify_event_silence`, WARN-only, degrades silently if git/script unavailable) so it fires on every `--quick` run automatically; confirmed firing live against this repo at build time (`recent_flips=109 has_event=0` — the exact pre-fix silence, since newly-authorized flips need time to accumulate ledger rows before the window clears). `verify-event-audit.sh` self-test 10/10 (was 7/0, scenarios 8-10 added, using real scratch git repos with real commits). Manifest: `plan-edit-validator` entry's `honest_status` updated to retire the stale "KNOWN PRE-EXISTING GAPS: HARNESS-GAP-62" claim; new `verify-event-silence` manifest entry (`kind: pattern`, `blocking: false`, full §10 fields). `manifest-check.sh` GREEN, 166 entries. HARNESS-GAP-63 (the awk double-print bug) remains open and unrelated — out of scope here as originally scoped.

- **HARNESS-GAP-63 — `check_evidence_first`'s prose-path awk double-prints "MATCH" (breaking the caller's exact-string comparison) whenever an EARLIER same-task-id block already satisfies it and a LATER block for the same task follows** (added 2026-07-30 from the harness-change-review REFORMULATE closure on `plan-edit-validator.sh`'s SE4 flip-ledger-emit code; label: `harness-gap`, `priority:medium`). PROVEN (direct awk repro, 2026-07-30): a two-block evidence.md where block 1 has `Task ID: X` + a `Runtime verification:` line (satisfying `in_block && task_id==wanted_id && has_runtime`) followed by a SECOND `EVIDENCE BLOCK` header for the same task prints `MATCH` TWICE — the main-body action's `print "MATCH"; exit 0` still runs the `END` rule afterward (POSIX awk semantics: `exit` outside `END` still executes `END` once), and `END`'s own condition re-evaluates true against the pre-reset state. The caller (`check_evidence_first`, `adapters/claude-code/hooks/plan-edit-validator.sh` ~L1429-1458) does `if [[ "$result" == "MATCH" ]]` — an exact-string comparison — so a genuinely-authorized flip (real evidence exists) is wrongly BLOCKED the moment a plan's evidence file accumulates 2+ same-task-id blocks where an earlier one already has a `Runtime verification:` line, exactly the FAIL-then-fix-then-PASS re-verification shape this repo produces routinely (see 3404bd1's T7 FLIP history). Confirmed the double-print reproduces with the exact awk body verbatim; NOT fixed here (out of the SE4 flip-EMIT finding's scope, which only touches the ledger-reporting awk in `_pev_extract_prose_flip_fields`, a structurally-similar but functionally distinct parser this task DID fix for the analogous first-match-wins bug). **Workaround used to keep this task's own F18 self-test fixture authorizable:** the fixture's first (stale) block omits `Runtime verification:` so it never satisfies `check_evidence_first`'s own condition, side-stepping the block without altering `check_evidence_first`'s code. **Fix (future session):** either replace the bare `exit 0` with a flag + `next` so the main loop consumes remaining input without letting `END` re-fire (mirroring the `record_if_match()`/`found` pattern this task's `_pev_extract_prose_flip_fields` fix now uses), or add a guard in `END` (`if (!printed) ...`). Add a self-test scenario asserting a real authorized flip against a two-same-id-block evidence file with an EARLY runtime-verification-bearing block succeeds (rc=0), not just that the ledger reports the right verdict once it does.
  (HARNESS-GAP-63 sibling, comprehension-review 2026-07-30): check_mechanical_or_contract_evidence's Path-B awk (plan-edit-validator.sh ~:1502-1513) carries the IDENTICAL print-MATCH-then-exit-0-then-END double-print shape — widen GAP-63's fix to both awks (sweep: rg -n 'print "MATCH"; exit 0' adapters/claude-code/hooks/plan-edit-validator.sh).

- **DOCTRINE-REVIEW-SURFACE-DECISION-OPEN-01 — `doctrine/**` (89 tracked files) is outside the review-record surface; the measured decision is written and awaiting the operator** (added 2026-07-30; label: `harness-gap`, `priority:medium`; **status: MEASURED, NOT LANDED — no surface change was made**). Decision record: `docs/decisions/069-doctrine-review-record-surface.md`. **Measured at `3caaeff` on BOTH `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15, agreeing:** over 90 days (`--since=2026-05-01`, `--no-merges`), **69** commits touched doctrine; **9** touched ONLY doctrine; **15** touched doctrine and NO already-in-surface file (= the true added friction, **1.16 commits/wk**, since records are keyed per-FILE so a doctrine+backlog.md commit gets no record today); **54** already require a record (adding doctrine widens the reviewer's diff but adds no round-trip). Pairs: **32** compact/`-full` pairs (64 files) + 2 orphan `-full` + 23 singletons = 89; **co-change rate only 57%** (48 both / 27 compact-alone / 8 `-full`-alone of 83 pair-touching commits), so the "one review covers two files" discount is weaker than assumed AND the 43% divergence is itself the harm mechanism. **Harm (PROVEN, 2 incidents):** (1) `orchestrator-pattern.md` carried the retracted "a quoted header … is inert" claim for ~52 min while its corrected `-full` sat beside it (`1394fe8` 17:47:58 fixed `-full` only; `b24f4ff` 18:39:48 fixed the compact); (2) `deterministic-process.md` shipped with a 3-part false ENFORCEMENT claim (`e91cdfa`), retracted by `b815b00` after a builder — not a gate — caught it; **both `e91cdfa` and `b815b00` are in the 15-commit zero-review set**. Coverage today: **3 of 293** review-index entries touch a doctrine path, all voluntary. **Options measured:** all-doctrine 89 files @1.16/wk (catches both); JIT-only 23 files @0.70/wk (**catches NEITHER**); JIT+CLAUDE.md-named 29 @0.85/wk (catches 1); `Enforcement:`-header-bearing 54 @1.01/wk (catches both, but content-derived surface). Recommendation in the decision record: **all-doctrine**, and **do not exempt "mechanical" cap-trim/INDEX commits** — 7 of the 15 are cap trims, and those are precisely the commits that rewrite delivered compacts most heavily (`2c74fe8` rewrote 5 compacts, `diagnosis.md` −112 and `evidence-before-fix.md` −180 lines; `6fc33cf` cut `orchestrator-pattern.md` 3451→2730B with NO change to its `-full` sibling, verified by `--numstat`). **Operator call, not landed here.**

- **DECISIONS-INDEX-GATE-DID-NOT-FIRE-FOR-066-068-01 — `docs/DECISIONS.md` is three records behind (`066`, `067`, `068` exist as files with no index row) despite a `blocking: true` gate that claims to enforce record↔index atomicity** (added 2026-07-30 while adding the row for `069`; label: `harness-gap`, `priority:medium`; constitution §10 theater class). PROVEN: `ls docs/decisions/` shows `066-macos-coord-sync-launchagent-and-credential-fix.md`, `067-review-independence-same-session-pathway.md`, `068-macos-limit-resume-turn-scoped-auto-arm.md`; `grep -n '^| 06[6-8]' docs/DECISIONS.md` returns **nothing**, and the index table's last row is `065` (2026-07-29). `adapters/claude-code/hooks/decisions-index-gate.sh` documents behaviour (a): a staged `docs/decisions/[0-9]{3}-.*\.md` with `docs/DECISIONS.md` NOT staged → BLOCK exit 1; the manifest entry `decisions-index` is `blocking: true` with `honest_status: "invoked via pre-commit-gate.sh chain"`, and that chain membership is real (`adapters/claude-code/hooks/pre-commit-gate.sh:124` lists `decisions-index-gate.sh`). So a gate that exists, is chained, and is declared blocking did not prevent three consecutive unindexed decision records. **Not diagnosed here** (out of scope for the doctrine-surface measurement; I did not determine WHICH of the three candidate causes applies). **Candidate causes to check, in order:** (a) `pre-commit-gate.sh` itself is not installed as the repo's actual `.git/hooks/pre-commit` on the machine those commits were authored on — the gate file's own header admits *"Not wired into the repo's pre-commit hook automatically. Follow-up task: extend `install-repo-hooks.sh`…"*, which directly contradicts the manifest's `honest_status`; (b) the records were committed with `--no-verify`; (c) the records landed in commits that staged them alongside a `DECISIONS.md` edit that did not actually add the row (behaviour (c) allows silently). **Fix:** determine which, then either wire the chain via `install-repo-hooks.sh` or correct the manifest `honest_status` to stop claiming enforcement that does not fire — per §10, wire it or delete the claim. Backfill rows for 066-068 either way.

- **REVIEW-SURFACE-COUNT-311-IS-FALSE-01 — the "surface was extended today from 283 to 311 files (`git-hooks/*`, `schemas/*.json`, `install.sh`, `sync.sh`)" claim is false at the branch tip; the executed count is 283** (added 2026-07-30 while measuring the doctrine decision; label: `harness-gap`, `priority:medium`; class: *number-carried-forward-from-a-draft*, the recurring defect on this branch). **PROVEN by execution, not grep:** sourcing the real `rrg_in_surface` from `adapters/claude-code/hooks/lib/review-record-gate-lib.sh` and running it over all **1762** tracked files at `3caaeff` yields **283** in-surface files — byte-identical file lists on both interpreters. The four claimed arms are **absent** from the `case` statement; the only surface change that landed today was Amendment G (cockpit product JS, `39a3dc3`). The archived plan `docs/plans/archive/deterministic-process-gate-2026-07-30.md` lists widening to `git-hooks/*` in its OUT-of-scope section verbatim — *"noted, not fixed in this pass"* — and repeats it under Assumptions as a "known residual". So the extension was **proposed and deferred, never landed**, and 311 describes nothing at HEAD. **Action:** anyone quoting a surface size must re-execute `rrg_in_surface` at the commit they are quoting; do not restate 311. **Note the `git-hooks/*` gap is real and still open** — the pre-push dispatcher that decides whether the authoritative review gate runs at all is itself unreviewed.

- **B24F4FF-COMMIT-MESSAGE-JIT-CLAIM-FALSE-01 — commit `b24f4ff`'s root-cause paragraph asserts `doctrine-jit.sh` injects `orchestrator-pattern.md`; it does not, and cannot** (added 2026-07-30; label: `harness-gap`, `priority:low`). The message states *"manifest.json entry[79] sets doctrine_file=\"doctrine/orchestrator-pattern.md\" and doctrine-jit.sh resolves THAT, so agents were being served the false version."* **The `doctrine_file` half is true; the resolution half is false.** That manifest entry has `jit_triggers.paths: []`, and `doctrine-jit.sh:229` (`[ "$paths_json" = "[]" ] && continue`) skips such entries outright — the hook's own self-test T8 asserts exactly this ("pattern-kind (empty jit_triggers) never fires"). **Verified BEHAVIOURALLY, not by reading:** executing the real hook against the real `manifest.json` across all **81** distinct trigger patterns injected `orchestrator-pattern` **0 times**, on both interpreters, with a passing control (`docs/plans/` does inject `artifact-evidence-bar`, proving the probe was live — the first probe run reported a false "0 hits" because the payload omitted `tool_name`, and only the control caught it). **The underlying harm claim still stands** by a different delivery path: `orchestrator-pattern.md` is named as required reading by `CLAUDE.md` and by 4 agent definitions (`plan-phase-builder`, `harness-reviewer`, `systems-designer`, `end-user-advocate`), so agents do read it — via prompt reference, not JIT. **Why this matters beyond the record:** it was the stated basis for "gate only the JIT-delivered compacts" as a cheap control, and that option provably misses this very file (see DOCTRINE-REVIEW-SURFACE-DECISION-OPEN-01). **Fix:** correct the causal sentence if the historical record is amended; more usefully, consider backfilling `jit_triggers.paths` for the high-traffic compacts that are currently referenced-but-never-injected.

- **PORTABILITY-TOUCH-D-SWEEP-01 — ~18 GNU-only `touch -d` callsites outside M4's `date -d` grep, same silent-failure class** (added 2026-07-29 from `docs/plans/macos-portability-2026-07.md` M4's build; label: `harness-gap`, `priority:medium`). M4 audited `grep 'date -d'` and fixed that class. While doing so it surfaced a SIBLING class the grep does not catch: bare `touch -d '<relative>'` / `touch -d "@<epoch>"` with no BSD fallback, which fails silently on macOS and leaves a fixture UN-AGED — so a staleness self-test asserts the opposite of its own name while still printing a verdict. Two such sites were inside M4's own files and were fixed (`concurrent-ownership-gate.sh:700` scenario 4, `:752` scenario 12 — the latter had been reporting PASS only because a sibling `date -d` bug had disabled the whole claim scan, i.e. two failures cancelling into a green). **Still open, one line each:** `session-start-digest.sh:1442`, `local-edit-gate.sh:291`, `stale-active-plan-surfacer.sh:339,362`, `lib/session-heartbeat-lib.sh:1046`, `lib/observability-derive.sh:2429`, `scripts/session-resumer.sh:2148,3104,3191`, `scripts/agent-heartbeat.sh:228`, `scripts/worktree-hygiene-sweep.sh:1090`, `scripts/f4-retro.sh:870,873,906`, `scripts/session-wrap.sh:388`, `hooks/cross-repo-nl-touch-warn.sh:463`. **Fix:** each becomes `nl_touch_age <file> <seconds>` from the helper M4 landed at `adapters/claude-code/hooks/lib/portable-time.sh` (sourced inside the self-test branch only, so production pays nothing), with NO `|| true` — the swallowed failure IS the bug. **DONE 2026-07-29 (M5):** all 19 executable sites converted across 12 files + 1 markdown recipe; `grep -rn "touch -d" adapters/claude-code` now returns comments only. Measured on stock macOS (BSD `touch`/`date`, UTC-7): 3 sites never aged at all, 5 more aged into the FUTURE because a `date -u` fallback was rendered in UTC and fed to a LOCAL-time `touch -t`. Suites recovered on BOTH bash 3.2.57 and 5.3.15: `session-resumer.sh` 51/31 -> 69/0, `worktree-hygiene-sweep.sh` 16/27 -> 37/6, `agent-heartbeat.sh` 18/1 -> 20/0, `session-heartbeat-lib.sh` 21/1 -> 22/0, `cross-repo-nl-touch-warn.sh` 10/1 -> 11/0.

- **PORTABILITY-STAT-SED-SWEEP-02 — audit for the remaining GNU-only coreutils spellings the `touch -d` sweep kept tripping over** (added 2026-07-29 from PORTABILITY-TOUCH-D-SWEEP-01's build; label: `harness-gap`, `priority:medium`). Three more GNU-isms were found incidentally while sweeping `touch -d`, each producing a wrong-but-silent value on macOS rather than an error: (a) `stat -c %Y` with no `stat -f %m` fallback — `scripts/agent-heartbeat.sh` used it as its corrupt-timestamp mtime fallback, so on macOS it ALWAYS returned the `|| echo 0` sentinel and the mtime was never read (this cancelled the un-aged fixture and made "corrupt-ts agent ages out via mtime fallback" green for entirely the wrong reason — both fixed under M5); (b) BRE `\|` alternation in `sed -n 's/...\(true\|false\).../\1/p'` — a GNU extension, so BSD sed matched nothing and `agent-heartbeat.sh`'s `--long` 3x-grace flag silently never applied (fixed under M5 with `sed -nE`); (c) a self-test re-invoking itself as bare `"$0"` on a file checked in mode 100644 — `worktree-hygiene-sweep.sh` did this 25 times, every one dying rc=126, which turned all 12 of its "must be SILENT" assertions into free passes (fixed under M5 with `"${BASH:-bash}" "$0"`). **Do:** grep the adapter for `stat -c`, `sed -n 's/.*\\(.*\\|`, and `$(\"\\$0\"` / bare `bash \"$0\"` outside a `${BASH:-bash}` guard, and add a `harness-claim-lint.sh` CLASS for each.

- **WHS-LIVENESS-JOIN-VAR-SYMLINK-03 — `worktree-hygiene-sweep.sh`'s heartbeat/claim join fails on macOS because `_norm_path` does not resolve `/var` -> `/private/var`** (added 2026-07-29 from PORTABILITY-TOUCH-D-SWEEP-01's build; label: `harness-gap`, `priority:medium`). Once M5 fixed the rc=126 re-invocation above, 5 previously-invisible failures surfaced and are REAL, not regressions: `S-g` (live heartbeat -> NOT flagged), `S-h` (mid-turn fresh transcript), `S-i` (throttled owner), `S-j` (CONTINUING within grace), `S-k` (fresh same-repo claim). All five are "a live owner must suppress the strand" assertions. Root cause (PROVEN by direct probe): `mktemp -d` returns `/var/folders/...` while `git worktree list --porcelain` reports `/private/var/folders/...`, and `_norm_path` (`adapters/claude-code/scripts/worktree-hygiene-sweep.sh:191`) only normalizes Windows/cygwin paths — it has no symlink resolution, so the fixture heartbeat's `worktree_root` never matches the worktree row and the join silently finds no owner. Same family as `session-wrap.sh`'s long-standing S7 failure (`expected /var/... got /private/var/...`). **Fix:** give `_norm_path` a real physical-path resolution step (`cd "$p" && pwd -P`) before the Windows branches. NOT attempted under M5 — out of that task's class.

- **PORTABILITY-GREP-PATTERN-01 — `grep 'date -d'` misses `date -u -d` and `date --date=`, so portability sweeps under-report** (added 2026-07-29 from M4's build; label: `harness-gap`, `priority:medium`). M4 was scoped by `grep -rn 'date -d'`, which does NOT match `date -u -d "$ts"` — the spelling used by `_hb_epoch` (`lib/session-heartbeat-lib.sh:280`), `_od_epoch` (`lib/observability-derive.sh:313`), `_ny_epoch` (`needs-you.sh`), and ~19 sites in `session-start-digest.sh`. Those happen to already carry BSD fallbacks, so nothing was broken by the omission — but the sweep would not have told us if they hadn't. **Fix:** M5's committed sweep runner must match the whole class, e.g. `grep -rnE "date ([^|;&]*)?(-d|--date)"`, and equally `touch -d`, `find -newermt`, `sed -i` w/o suffix, `stat -c`, `timeout`.

- **PORTABILITY-BASH32-ASSOC-ARRAYS-01 — `declare -A` in `observability-derive.sh` breaks it on bash 3.2.57 (macOS `/bin/bash`)** (added 2026-07-29 from M4's build; label: `harness-gap`, `priority:medium`; **STATUS 2026-07-29: PARTIALLY IMPLEMENTED** — the three named files are fixed and proven under both interpreters, see `docs/plans/macos-portability-2026-07.md` M6 entries. The severity was worse than this entry states: `hooks/scope-enforcement-gate.sh:1849` had the same defect and it is a BLOCKING PreToolUse gate — under 3.2 it printed `declare: -A: invalid option` and then **exited 0**, authorizing every out-of-scope commit, while its `--self-test` reported 35/0 because all 14 child invocations went through a PATH-resolved bare `bash` (Homebrew 5.3) instead of the interpreter under test. Remaining sites are tracked in PORTABILITY-BASH32-ASSOC-ARRAYS-02 below.). PROVEN: `lib/observability-derive.sh:814` (`declare -A _od_waiting_set=()`) and `:1231` (`declare -A gate_block gate_waiver gate_downgrade`) use associative arrays, a bash 4.0 feature. `adapters/claude-code/hooks/lib/perf-tick-snapshot.sh:319` has the same defect (`local -A`, observed erroring as `local: -A: invalid option` in that suite's bash-3.2 run). The declared portability floor for this harness is bash 3.2.57, since that is macOS's `/bin/bash`. Measured: `observability-derive.sh --self-test` PASSES on bash 5.3 + GNU and FAILS on bash 3.2 regardless of toolchain. NOT a `date` issue and out of M4's scope. **Fix:** either replace the assoc-array uses with the parallel-array / delimited-string idiom used elsewhere in this repo, or explicitly raise the declared floor to bash 4+ and document that macOS `/bin/bash` is unsupported (the operator's `env.PATH` already prefers Homebrew bash 5.3, so this is defensible — but it must be a STATED decision, not an accident).

- **PORTABILITY-BASH32-ASSOC-ARRAYS-02 — 7 more files still use bash-4 associative arrays; the original grep missed `local -A` and `declare -gA`** (added 2026-07-29 from M6's build; label: `harness-gap`, `priority:medium`). PROVEN by `grep -rnE '(declare|local|typeset)[[:space:]]+-[A-Za-z]*A' adapters/claude-code`: the sweep that produced ARRAYS-01 searched only for the literal `declare -A`, which matches neither `local -A` nor `declare -gA`. The true remaining inventory, all unfixed: `hooks/lib/observability-derive.sh` — 9 `declare -gA` globals (`_OD_TRANSCRIPT_INDEX`, the 7 `_OD_HB_*` heartbeat field maps, `_OD_COSTS_CACHE`, plus `_OD_BLOCK_EPOCH_BY_SID` / `_OD_THROTTLE_EPOCH_BY_SID`); `hooks/session-start-digest.sh:297,298`; `hooks/decision-context-pending-surfacer.sh:348`; `scripts/close-plan.sh:888`; `scripts/waiver-density.sh:195`; `scripts/remap-placeholder-ask-events.sh:195`; `scripts/read-local-config.sh` (6 sites, `_NL_CONFIG_CACHE`); `scripts/estate-janitor.sh:305,370,509,540`. (`attic/completion-criteria-gate.sh:356` is retired — leave it.) **Fix:** same two idioms M6 used, chosen per access pattern — parallel indexed arrays when the consumer needs key+value together or enumerates keys, a delimited string + `case` when it is pure membership with delimiter-safe keys. **Also required:** every `--self-test` in the affected files must re-invoke children with `"$BASH"`, never a bare `bash`, or the suite will report green for an interpreter it never ran (this is what hid the whole class). A static scenario asserting the file contains no bash-4 construct — as added to `scope-enforcement-gate.sh` (scenario 35) and `lib/perf-tick-snapshot.sh` (scenario 8) — makes the guard fire even on a 5.x-only run.

- **PORTABILITY-FIND-PRINTF-01 — GNU-only `find -printf` silently empties the transcript index on macOS** (added 2026-07-29 from M6's build; label: `harness-gap`, `priority:medium`). PROVEN: `adapters/claude-code/hooks/lib/observability-derive.sh:271` builds `_OD_TRANSCRIPT_INDEX` from `find "$dir" -maxdepth 4 -type f -name '*.jsonl' -printf '%f\t%p\n'`. BSD `find` has no `-printf`, so the command fails and the `while` loop reads nothing — but `_OD_TRANSCRIPT_INDEX_BUILT` is set to 1 regardless, so every subsequent `_od_find_transcript` lookup returns empty INSTEAD of falling back to the working per-call `find`. HYPOTHESIZED (refuter: fix the `find` and re-run) that this is the root cause of the 9 `od_costs` / `od_sessions` self-test failures that fail identically on bash 5.3 AND 3.2 (`expected exactly 2 session(s) costed, got: 0 session(s) costed`). Deliberately NOT fixed in M6 so that commit's before/after failure comparison stayed clean. **Fix:** `find ... -type f -name '*.jsonl' -print` and derive the basename in the loop, or `-exec basename` — plus set `_OD_TRANSCRIPT_INDEX_BUILT=1` only when the build actually produced rows.

- **PORTABILITY-RESIDUAL-BSD-FAILURES-01 — 2 self-test suites fail on BSD for non-`date` reasons, not root-caused** (added 2026-07-29 from M4's build; label: `harness-gap`, `priority:low`). After M4, the `date -d` sweep set stands at 14/19 passing on stock macOS vs 16/19 with the GNU toolchain. The 2-suite gap is NOT `date`: (a) `harness-doctor.sh` — scenarios `o6-obs-scheduled-tasks-red` and `o6-obs-scheduled-tasks-red-names-task` fail on BSD only; `scripts/scheduled-task-health.sh` contains no `grep -P`/`sed -i`/`timeout`/`date -d`, so the cause is unidentified (HYPOTHESIZED: another BSD/GNU tool divergence in the fixture's `schtasks` stub path; refuter: run the scenario with each userland tool individually swapped). (b) `lib/session-heartbeat-lib.sh` — `hb_classify throttled scenario failed`, BSD only. Both were pre-existing before M4 and are unchanged by it. Separately, `scripts/worktree-hygiene-sweep.sh` and `lib/perf-tick-snapshot.sh` fail under BOTH toolchains (environmental / Windows-WINPID respectively) — pre-existing, unchanged, and out of scope.

- **PORTABILITY-SELFTEST-EXCLUSION-ALLOWLIST-RECONCILE-01 — two exclusion mechanisms now exist; the CI one is basename-keyed and documented as vestigial** (added 2026-07-29 from `docs/plans/macos-portability-2026-07.md` M6's build; label: `harness-gap`, `priority:medium`). M6 shipped the path-keyed ledger `adapters/claude-code/config/selftest-sweep-exclusions.txt` + reader `adapters/claude-code/scripts/selftest-sweep-exclusions.sh` (`--list` is the sweep-runner API). The pre-existing mechanism is `KNOWN_FAILING_HOOKS` inside `.github/workflows/hooks-selftest.yml` — a bash array embedded in GitHub-Actions YAML, keyed by BASENAME. The two are not reconciled, deliberately: they cover different sets (CI's list includes LIVE hooks like `workstreams-emit.sh`, which the M6 ledger's C3 control forbids by design — a live control gets fixed or retired, never excluded), and per `docs/findings.md` NL-FINDING-018 the CI entries for `decision-context-gate.sh` / `decision-context-replay.sh` are ALREADY vestigial, because CI globs `adapters/claude-code/hooks/*.sh` and never sweeps `attic/` at all. **Two real defects live in that basename keying:** (1) `decision-context-gate.sh` cannot distinguish the attic original from the live 3-line exit-0 shim of the same basename; (2) the live entries silence live hooks with no expiry and no doctor predicate. **Fix:** decide ONE owner. Either teach the CI job to consume `--list` for the retired set and keep `KNOWN_FAILING_HOOKS` only for live cold-CI failures with a stated expiry, or migrate the whole allowlist to the ledger and give the live entries their own C3-exempt class with a retirement condition each.

- **PORTABILITY-ATTIC-SELFTESTS-NOT-SELF-CONTAINED-01 — the two excluded attic self-tests fail for environment reasons, and the same class silently degrades a LIVE hook** (added 2026-07-29 from M6's build; label: `harness-gap`, `priority:low`). Both M6 exclusions are the HARNESS-GAP-42 "accumulated-state-vs-cold-environment" class, PROVEN not hypothesized: `attic/decision-context-gate.sh` degrades to its NOENV branch because `neural-lace/workstreams-ui/state/decision-context-schema.js` requires `zod` and `neural-lace/workstreams-ui/node_modules` is gitignored and uninstalled (reproduced from the suite's own kept ST5 fixture under a sandboxed `HOME`; the gate's own log line reads `Tier 1 fence — env unavailable (schema-require:Cannot find module 'zod')`, and it then neither blocks nor writes state). `attic/workstreams-extract-pending.sh` resolves a SIBLING `workstreams-emit.sh` relative to its own directory, but that sibling was never retired. **The part that is NOT retired and therefore matters:** the LIVE `adapters/claude-code/hooks/workstreams-emit.sh` resolves the SAME zod-dependent schema module (its `_resolve_schema_module`, ~line 720) and calls it the "SOLE-NORMATIVE assembler". Its `--self-test` currently passes, so whatever it does when the module is unloadable is a degrade path nothing asserts. **Fix:** (a) assert the live emitter's schema-unavailable degrade path explicitly rather than leaving it untested, and (b) decide whether a `npm ci` in `neural-lace/workstreams-ui` becomes a documented precondition of the self-test sweep — if it does, both M6 exclusions become deletable and the ledger's C4 control will WARN that they are stale.

- **INBOX-MY-ITEMS-RELOCATION-01 — operator-authored "My items" section not yet built inside the Inbox view** (added 2026-07-19 from cockpit-roadmap-redesign Task 4's build; label: `workstreams-ui`, `priority:medium`). Task 4's own plan bullet (A10) describes operator-authored freeform items rendering as a distinct "My items" section within the new Inbox view (`neural-lace/workstreams-ui/web/inbox.js`), excluded from the Inbox (N) headline count. Task 8's OWN bullet ("the standalone My-To-Do pane REMOVED — its operator-authored items move into the Inbox 'My items' section per A10/task 4") claims ownership of BOTH the removal of the standalone pane (`todo.js`, in the Requests tab sidebar) AND the relocation of its items as one unit of work — task 4's dispatch explicitly said "do NOT retire if assigned to task 8". Task 4 therefore ships the Inbox (N) count/answerable/quarantined split WITHOUT a "My items" section; `todo.js` and the standalone pane are completely untouched. **Fix (task 8):** build the "My items" section inside `web/inbox.js` (reusing `todo.js`'s `/api/todo` GET/POST contract + edit machinery — either by genericizing `todo.js` into a mountable function called from both containers, or a second small duplicated renderer per this codebase's own established small-helper convention), THEN remove the standalone pane markup from `web/index.html`'s Requests-tab sidebar.

- **ROADMAP-WAITING-ON-YOU-SIGNAL-01 — no roadmap item is ever computed as "stalled: waiting-on-you" pointing at a specific needs-you ledger id, so the Inbox's "blocks: `<item>`" chip has no live data source** (added 2026-07-19 from cockpit-roadmap-redesign Task 4's build; label: `workstreams-ui`, `priority:medium`). Task 1's `deriveItemStatus()`/`deriveStalledReason()` (`neural-lace/workstreams-ui/server/derive-lib.js:586-596`) accept a caller-supplied `stalledSignals.waitingOnYouId` per roadmap item, but `server/roadmap-routes.js` (task 3) never populates it — there is no code path today that correlates a specific roadmap item/task to a specific needs-you (`NY-...`) ledger id. Task 4's Inbox view (I5 collapsed-row anatomy: "blocks: `<item>`", linking `#roadmap/<id>`) therefore always renders `blocks_roadmap_id: null` (`server/inbox-routes.js`'s own documented HONEST LIMIT) — the chip never appears, by construction, never fabricated. **Fix:** wire `roadmap-routes.js` to look up, per roadmap item, whether any open needs-you ledger item's `session` field matches a live/known session tied to that item's plan/task (or a more direct correlation if one gets designed), and populate `stalledSignals.waitingOnYouId` accordingly; then `inbox-routes.js`'s `buildInboxItem()` can do the reverse lookup and stop hardcoding `null`.

- **UX-REDESIGN-CONVERGE-01 — converge sit-down into redesign plan** (added 2026-07-17; priority:high). **FOLD-INTO 2026-07-18** → absorbed by docs/plans/cockpit-roadmap-redesign.md (DRAFT; 5-round synthesis complete; awaiting arch+ux gates).

- **WS-UI-STATUS-PAGE-ADOPTION-01 — evaluate folding the "Overnight Run Status" page design into the live Workstreams UI** (added 2026-07-15; operator liked the artifact and wants a ws-UI session to consider it; label: `ws-ui`, `design`, `priority:low`). Full reference + design analysis + the artifact URL live in `docs/design-notes/status-page-for-ws-ui-adoption.md`. The page is a static claude.ai artifact (https://claude.ai/code/artifact/47636abb-dd82-4d2c-b294-326908ed3d77) — NOT a ws-UI view. Candidate patterns to adopt: a top-of-page status-verdict banner (green only when both NEEDS-YOU buckets are empty), live stat tiles, per-mechanism LIVE/doctor-state chips, terminal palette. Constraint: ws-UI must DERIVE these from live state (plans / NEEDS-YOU / doctor / worktrees), not hand-author. Separate track from the harness-governance follow-up batch (`docs/handoffs/2026-07-15-followup-batch-handoff.md`).

- **SESSIONSTART-SINGLEFLIGHT-01 — heavy SessionStart hooks have no single-flight lock; concurrent sessions stack them into a fork storm that pins Windows Defender at ~50% CPU** (added 2026-07-12 from live diagnosis, operator-reported Task Manager screenshot; label: `harness-gap`, `priority:medium`; nl-issue filed same day). **Observed (PROVEN, this session):** ~4 concurrent logical invocations of `harness-doctor.sh --quick` plus simultaneous instances of `session-start-digest.sh` (incl. `--self-test` runs), `session-start-auto-install.sh`, `gen-architecture-diagram`, and `plan-deletion-protection.sh` — 34 live bash.exe processes, 25 started within 5 minutes (survivors only; each logical hook shows as 2–3 bash.exe via the Git Bash `bin\`→`usr\bin\` launcher chain). With 68 hook commands registered globally (35 on PreToolUse) and 15 claude processes (multiple sessions each firing 8 SessionStart hooks), process-creation rate is extreme. **Effect (HYPOTHESIZED, high confidence; refuter: `New-MpPerformanceRecording`/`Get-MpPerformanceReport` elevated run):** MsMpEng real-time protection scans every process create + file open — observed at 48.9% CPU (Task Manager, 2026-07-12), the classic fork-heavy-Git-Bash-without-exclusions signature. **Fix (two independent parts):** (1) per-machine lockfile/debounce (mkdir-lock with stale-TTL, since flock is unreliable on MSYS) for the heavy SessionStart scripts — a second session arriving while doctor/digest/auto-install runs should skip or consume the in-flight run's cached output rather than re-run; gen-architecture-diagram and digest `--self-test` invocations are candidates for demotion out of SessionStart entirely. (2) Document operator-side Defender guidance (process exclusions for bash.exe/git.exe, tradeoffs stated) in harness-dev doctrine — operator action, never agent-applied (security-settings changes are operator-only). Golden scenario: 2026-07-12 Task Manager observation. Fold-in: next SessionStart/perf touch or standalone after harness-reviewer PASS on the lock semantics. **PARTIALLY LANDED 2026-07-13 (`docs/plans/lessons-learned-fixes-2026-07-13.md`):** part (1) lock — `hooks/lib/sessionstart-singleflight.sh` ttl-debounce now gates `session-start-auto-install.sh` (the git-fetch + full-sync fork-storm source); digest intentionally left ungated (per-session operator output). part (2) Defender guidance — the `scripts/host-setup/setup-defender-exclusions.ps1` helper + `docs/host-setup/windows-defender-exclusions.md` already ship (operator runs under UAC). **STILL OPEN:** demoting `gen-architecture-diagram` / digest `--self-test` out of SessionStart, and gating the remaining heavy SessionStart scripts if a fork-storm persists after the auto-install debounce.

**LANDED 2026-07-23 (`docs/plans/agent-efficiency-fixes-2026-07.md` T2/T3, recurrence diagnosed in `docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md`):** the 07-20 recurrence traced the ACTUAL dominant driver — NOT digest's own `--self-test` entry point (which is never reached from SessionStart) but `harness-doctor.sh`'s `check_wave_e_surfaces` E.1 predicate, which EXECUTED the full `session-start-digest.sh --self-test` suite (~19 scenarios, no timeout) INLINE and UNCONDITIONALLY as part of `run_quick_checks` — i.e. on every SessionStart AND resume, contradicting the doctor's own documented "--quick ... Never runs self-tests. Fast (<2s typical)" contract. Live capture mid-storm: 7 concurrent 12+-minute digest self-test runs + 3 concurrent doctor `--quick` runs, 94 bash.exe total. **Fixed:** (1) E.1 predicate now does a structural check only (exists/executable/declares `--self-test`), matching the sibling E.7/E.8 predicates — the real suite execution is `check_selftest_sweep`'s job (`--full` only, already timeout-guarded, now also reentry-guarded); (2) `session-start-digest.sh`'s `--self-test` entry point now honors the NL-FINDING-040 reentry guard (previously didn't, unlike its default case); (3) `gen-architecture-doc.sh` confirmed NOT event-wired (manifest: "not event-wired (manual + doctor-invoked)") — that part of "STILL OPEN" above was already moot; (4) SESSIONSTART-SINGLEFLIGHT-01's lock extended (per dispatch) to `harness-doctor.sh`'s SessionStart-quick call (global lock, `doctor-quick`) and `session-start-digest.sh`'s default SessionStart call (per-repo-root lock via the new `ss_repo_key` helper) via a new `NL_SESSIONSTART_ORIGIN=1` marker settings.json.template's SessionStart wiring passes — explicit/manual invocations are never affected. **Follow-up (not built, lower priority):** an hourly health-tick-driven cache of the digest's last self-test verdict so `--quick` can WARN with detail between `--full` runs instead of going silent on a genuinely-broken digest hook (the fidelity this fix traded away).

- **HOOK-SHIM-RETIRE-01 — one retired `exit 0` shim (`workstreams-state-gate.sh`) is still wired live + in the install template; retire it to save a wasted subprocess per builder-dispatch / spawn-task** (added 2026-07-13 from the agent-efficiency lesson rec 3, `docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md`; label: `harness-gap`, `priority:low`). The lesson named `tool-call-budget.sh`, which is already gone from live + template (only the dead gitignored `settings.json` still wires it). But `workstreams-state-gate.sh` (RETIRED Wave-O, pure `exit 0`) is still wired TWICE in `settings.json.template` (`Task|Agent|Workflow --builder-tracking` + the mcp spawn matcher) and TWICE live. **TEMPLATE-SIDE FIX LANDED 2026-07-23** (`docs/plans/agent-efficiency-fixes-2026-07.md` T5, commit `bf0acf9`): both wirings removed from `settings.json.template`; the `hooks/workstreams-state-gate.sh` shim file hard-deleted (full original already preserved at `attic/workstreams-state-gate.sh` from the earlier Wave O.4 retirement — commit `568daa0`); `install.sh`'s `PRUNED_FILES` gained an entry so a future `install.sh` run removes the stray live copy; the `manifest.json` entry removed (no artifact left to describe); the shim header's false "not wired" claim is moot (the file no longer exists). Root-caused: commit `b71456d` (2026-07-12, an earlier template-live-drift "fix") re-added the two wirings by copying FROM an already-drifted live `settings.json` instead of reconciling live TO the retirement — that is how this item's own "still wired TWICE" state re-occurred after Wave O.4 had already retired it once. **STILL OPEN (not done 2026-07-23, by design — see that commit's HONESTY GAP note):** `session-start-auto-install.sh`'s `merge_settings()` is additive-only with NO removal path for the two hook entries already merged into live `~/.claude/settings.json` on any machine that ran auto-install before 2026-07-23 (this machine's own live settings.json was confirmed, 2026-07-23, to still carry both entries). No settings.json-entry reconcile mechanism exists anywhere in the codebase — building one was explicitly out of scope for a single builder task per the dispatch instructions ("file the gap... rather than inventing a new mechanism unreviewed"). Fix still needed: EITHER a settings-maintenance-window manual live reconcile (per this item's original "Fix" text) on each already-installed machine, OR a durable settings.json reconcile-on-diff mechanism (its own plan — same blast-radius caution as PRETOOLUSE-DISPATCHER-01 below: touches every machine's live hook wiring). Golden scenario: efficiency lesson §7 rec 3 (still the reference incident); template-fix evidence: efficiency-fixes plan T5 commit `bf0acf9`.

- **PRETOOLUSE-DISPATCHER-01 — coalesce the ~20 per-Bash PreToolUse hooks into one in-process dispatcher** (added 2026-07-13 from the agent-efficiency lesson rec 4, `docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md`; label: `harness-gap`, `priority:medium`). Every Bash tool call currently fires ~20 separate `bash ~/.claude/hooks/<x>.sh` processes, each re-spawning bash + re-parsing `tool_input` independently — the per-call process-spawn tax the lesson quantifies. Proposal: one `pretooluse-dispatch.sh` that reads `tool_input` ONCE, then runs each check as an in-process shell function, preserving each check's exit-code/block-message contract (CC blocks on the first non-zero exit + surfaces its stderr, so a sequential dispatcher can short-circuit correctly). **Why deferred (its own plan, not the lessons-fixes plan):** HIGH blast radius — the dispatcher becomes a single point on EVERY Bash call; needs a full plan + `harness-reviewer` + staged rollout + a `--self-test` proving each check still blocks its golden scenario and precedence is preserved. Risks flagged: shared-env/global bleed between sourced checks, a check's `set -e`/`exit` killing the dispatcher, reentry-guard semantics under a shared process, loss of per-hook CC timeout isolation. Golden scenario: efficiency lesson §7 rec 4.

- **CLAIM-LIFECYCLE-01 — session-end unclaim for concurrent-ownership claims** (added 2026-07-12 from harness-review round 1 of concurrent-ownership-gate, FIX 2; label: `harness-gap`, `priority:low`). Claims (broadcast-active-session.sh v2) are written at SessionStart and refreshed at each Stop hook, but nothing removes them when a session ends — a claim persists up to 2h (mtime freshness) past the last turn, so another session hitting the owned plan/branch in that window gets a stale-claim block (the structured waiver is the valve; documented in the gate's KNOWN LIMITS + manifest fp_expectation). Wiring needed: `broadcast-active-session.sh unclaim` on a genuine session-END event (Stop is per-turn — unclaiming there would strip protection mid-session). If/when a SessionEnd hook event is verified available in the installed Claude Code, splice unclaim there; until then the 2h staleness window is the accepted cost.
- **SHARED-CHECKOUT-BRANCH-GUARD-01 — mechanical guard against builders/orchestrators committing on the shared main checkout's wrong branch** (added 2026-07-09 from nl-issue [34] triage, sweep plan R1; label: `harness-gap`, `priority:medium`). Live incident 2026-07-07: a worktree-isolated builder ended with the SHARED main checkout switched to its build branch; the orchestrator's next merge landed on the wrong branch. Proposal (needs harness-reviewer + constitution §10 golden-scenario/FP-rate case before build): a PostToolUse/Stop check that the main checkout's current branch is `master` when a worktree-isolated agent terminates, or a deny on non-master `checkout` in the main checkout from agent sessions. Golden scenario: the 2026-07-07 O.4-fix1 incident. Fold-in: any future orchestration-hardening plan, or standalone after reviewer PASS.

- **CRED-403-JIT-TRIGGER-01 — preemptive credentials/account-map injection when a session touches a provider/deploy surface** (added 2026-07-09 from nl-issue [46] triage, sweep plan R1; label: `harness-gap`, `priority:medium`). Incident 2026-07-08: a session guessed a cloud team slug → 403 → told the operator "reconnect the integration" when the connector was already authed on the other account. Proposal (needs harness-reviewer): doctrine-jit keyword trigger (vercel, deployment, cron, 'env pull', 'team slug', '403', 'no access', 'reconnect') injecting the credentials-reference account-and-scope map BEFORE the guess; cheaper alternative: extend the PostToolUse gh-404 hint to MCP/CLI 403s. Golden scenario: any session that 403s on a guessed cloud identifier and concludes "missing access". Fold-in: doctrine-jit trigger inventory.

- **COLD-READER-MECH-LAYER-01 — mechanical layer for the cold-reader decision bar** (added 2026-07-09 from nl-issue [40] triage, sweep plan R1; label: `harness-gap`, `priority:medium`; operator directive 2026-07-06 — THE recurring pain). Three parts, WARN-only per ADR-059 D7: (1) needs-you.sh add validates decision entries against the cold-read bar (v1 lint EXISTS and false-flagged a structured entry 2026-07-09 — see nl-issue [51]'s sibling row for the negation fix; the validator needs the §3-shape-aware rewrite, not bare keyword checks); (2) Stop-side WARN for final-message decision blocks lacking an artifact anchor or per-option outcomes; (3) AskUserQuestion three-question anatomy in doctrine + reviewer checklist. Former owner (observability program) is COMPLETED — needs a new home. Fold-in: next decision-surfaces/UX-of-operator-comms plan.

- **BG-AGENT-AUTO-RETRY-01 — auto-retry/resume for background agents killed by terminal API errors pre-final-write** (added 2026-07-09 from nl-issues [43]/[44] triage, sweep plan R1; label: `harness-gap`, `priority:low` — partially mitigated upstream). Two live instances 2026-07-07 + two more 2026-07-09 (Fable spend-limit killed a harness-reviewer mid-verdict and a research agent; SendMessage transcript-resume recovered the reviewer fully). ADR-061 D7 covers detection/surfacing of orphans; this row is the ACT half: an orchestrator-side retry policy (resume-from-transcript once, after the limit class clears) rather than a harness hook — Claude Code ≥2.1.19x also auto-retries transient errors natively (CLI upgrade prerequisite in ADR-061). Fold-in: ADR-061 Phase 3.

- **PERF-BUDGET-SELFTEST-01 — perf-budget self-test fixture class for O(rows×spawn) pathologies** (added 2026-07-09 from nl-issue [41] triage; label: `testing`, `priority:medium`). Recurred 4×: bash per-line subprocess loops over unbounded files pass tiny fixtures, then blow up on real-scale data (caught only by livesmoke). Mechanism: a shared self-test scenario pattern that synthesizes a ~200-row/2000-line fixture and asserts the oracle answers <5s, failing O(rows×spawn) pre-merge. ADR-061 D1's live-scale supervisor self-test is the first instance; generalize into testing doctrine + a reusable fixture helper. Fold-in: testing-doctrine next touch or ADR-061 Phase 1 (extract the helper).

- **GH-AUTH-RACE-01 — machine-global gh auth account races between concurrent sessions** (added 2026-07-09 from nl-issue [64] triage; label: `harness-gap`, `priority:medium`). 3+ flips in one session: parallel sessions/builders switch the keyring's active account mid-command; a push that worked 404s seconds later. Fix candidates (needs harness-reviewer): pin pushes/PR-ops with per-command `GH_TOKEN` env (no global state), or a retry-with-switch wrapper in git doctrine, or worktree-scoped `gh auth` config. Golden scenario: this session's 2026-07-09 batch-1 push failing between two commands. Fold-in: git doctrine next touch.

- **INSTALL-SYNC-PARITY-01 — auto-install SYNC_SUBDIRS missing pipeline-prompts/pipeline-templates/commands (reverse of nl-issue [31])** (added 2026-07-09 from nl-issue [60] triage; label: `harness-gap`, `priority:low`). install.sh now ⊇ auto-install (batch 1, 4504db0) but the reverse gap remains: merges touching the three install-only dirs don't reach live ~/.claude until a manual install run. Fix needs recursive handling (auto-install's sync is flat .md-only; skills/nl-issue/ already exposes this). Fold-in: next auto-install/installer-parity touch.

- **CLAUDE-PREVIEW-WORKTREE-01 — Claude_Preview MCP resolves launch.json from the parent worktree (upstream limitation, DOCUMENTED)** (added 2026-07-09 from nl-issue [32] triage, sweep plan R2; label: `upstream`, `priority:low`). The Preview MCP child reads `.claude/launch.json` from the PARENT worktree and ignores the agent worktree's copy + requested config name; a stale entry can launch a retired server on the shared port (bit the O.4 acceptance run). No harness-side fix available; workaround: kill the MCP child manually or align the parent worktree's launch.json before agent preview runs. Revisit if the Preview tool gains per-worktree resolution upstream.

- **NL-FINDING-037 — `purge-selftest-pollution.sh --apply` always exits 1 regardless of actual outcome** (added 2026-07-06 from nl-issue triage, reported by the 034-fixer session; label: `harness-gap`, `priority:medium`; REPRODUCED live this session in a sandboxed `HOME` override — no real `~/.claude` state touched). **Root cause.** The script has `set -e` (line 4) and its final statement is `[[ "$APPLY" == false ]] && echo "(dry-run; use --apply to remove)"`. Under `--apply`, `APPLY=true`, so the `[[ ... ]]` test is false; with `&&` short-circuiting, the whole compound statement's exit status is 1; as the LAST command in the script under `set -e`, this makes the script itself exit 1 even when every actual purge step succeeded. Any caller checking the exit code (a cron wrapper, a doctor predicate, an operator script) sees a false failure indistinguishable from a real one. **Fix.** Add an explicit `exit 0` after the conditional (or rewrite as an `if/else` with an explicit `exit 0` on both arms), plus a full-script `--apply` self-test scenario (the existing `--self-test` mode only exercises the internal `_purge_file`/`_purge_backup_files` helpers in isolation, not a full end-to-end `--apply` invocation's own exit code). File: `adapters/claude-code/scripts/purge-selftest-pollution.sh`.

- **PROGRESS-FIELD-01 — plan-checkbox lag has no interim signal between "not started" and "verifier flips `[x]`"** (added 2026-07-06 from nl-issue triage, operator-requested 2026-07-04, design resolved by operator 2026-07-04; label: `planning`, `priority:medium`). **Problem.** An unchecked `- [ ]` box is silent about whether a task is not-yet-started, mid-build, code-complete-but-unwired, wired-but-unverified, or blocked — all render identically, and the verifier-only-flips-`[x]` invariant (constitution — task-verifier is the only checkbox-flipper) must not be broken to fix this. **Resolved design (operator, 2026-07-04):** a single enum-constrained `Progress:` STATUS field per task, NOT per-stage sub-checkboxes. Rationale: sub-checkboxes would 4x the verifier-integrity surface (each box needs its own who-flips-on-what-evidence answer, reintroducing self-reported completion or 4x verify cost), impose a uniform lifecycle on non-uniform tasks (N/A-box noise), and split the authoritative done-bit; a status field keeps ONE verifier-only checkbox and carries the lifecycle as ordinal metadata (the Done-when already enumerates stages, so boxes would duplicate it). **Enum vocab (validator-checked):** `not-started|building|code-complete|wired|installed|verify-pending|blocked`. **Three-part fix (additive, zero risk to the invariant):** (1) add the builder-set `Progress:` field to the plan template + `plan-edit-validator` warn-when-absent — fold into specs-f §F.2b docs-as-process (NOT the same mechanism as F.2b's `Docs impact:` field — that ships already; this is a separate field); (2) auto-invoke `task-verifier` on merge for merge-satisfiable Done-whens, with a `verify-at: cutover` opt-out for tasks that can only be verified at a later integration point — fold into Wave F.5 gate governance; (3) a read-only `nl plan-status` derived view computing task reality from ground truth, never touching the checkbox — fold into observability §O.3 derivation lib. **Negative-effect guard:** every part must preserve the verifier's monopoly on `[x]` — the `Progress:` field is metadata, not a second done-bit. **End state:** O.3's `nl status` derives Progress-equivalent signal from ground truth directly; the hand-set field is the interim until then. Cross-ref: `docs/plans/nl-overhaul-program-2026-07-specs-f.md` §F.2b; `docs/plans/nl-observability-program-2026-08.md` §O.3.

- **MANIFEST-NEEDS-YOU-DRIFT-01 — live `manifest.json`'s `needs-you-ledger` entry has empty `hooks`/`keywords`, diverging from its own fixture** (added 2026-07-06 from nl-issue triage, F.2/manifest-regen follow-up; label: `harness-gap`, `priority:low`). **Verified live** (`adapters/claude-code/manifest.json`, entry id `needs-you-ledger`, kind `writer`): `"hooks": []`, and `jit_triggers.keywords: []`. The fixture at `adapters/claude-code/tests/fixtures/wave-e/E.6/manifest-entry.json` specifies `"hooks": ["scripts/needs-you.sh"]` and `jit_triggers.keywords: ["needs-you", "NEEDS-YOU", "awaiting your decision"]` — the live entry never picked those up. Not part of any E.6/E.12 Done-when (doctor is currently GREEN despite the drift — the predicate doesn't check hooks/keywords population for this entry). **Fix:** regenerate this entry from the fixture via the F.2 manifest-regeneration tooling (`gen-architecture-doc.sh` / `manifest-check.sh --gen-index`) rather than hand-editing the ~900-line manifest.json directly, to avoid introducing a fresh hand-drift.


- **RESUMER-SCHEDULED-EXIT1-01 — `NL-session-resumer` scheduled task still exits 1 on every tick after both the PATH-export and jq-fallback fixes** (added 2026-07-06 from nl-issue triage; label: `harness-gap`, `priority:high`; REPRODUCED live this session). **Symptom.** `schtasks /Query /TN "NL-session-resumer" /V` shows `Last Result: 1` on the most recent tick. The live task's `/TR` already runs `"C:\Program Files\Git\bin\bash.exe" -c "export PATH=/usr/bin:/mingw64/bin:$PATH; cd '.../neural-lace' && RESUMER_SHADOW=1 bash adapters/claude-code/scripts/session-resumer.sh"` — i.e. the PATH-prefix mitigation named in the original nl-issue entry (2026-07-06T15:47Z) IS applied on the live machine. The jq-invocation-failure fallback fix (commit `fbbfc19`, master) is also live. **Yet the identical command still returns exit 1 from the Task Scheduler context** while running the SAME command manually from interactive Git Bash in this session returned exit 0 — confirming a real, still-unresolved environment delta between the two invocation contexts (SYSTEM/Task-Scheduler non-interactive bash.exe vs. interactive Git Bash), not fully explained by PATH or jq alone. **Fix:** capture stdout+stderr from an actual scheduled-task run (redirect `/TR` output to a log file, or wrap the command in `... > "$LOG" 2>&1; echo $? >> "$LOG"`) to get the real failure signal instead of inferring from the interactive-shell repro; likely candidates remaining: a second PATH-dependent tool beyond jq/node, a working-directory assumption that differs under Task Scheduler, or `set -e`/`set -u` tripping on a var that's only unset in the non-interactive shell. Cross-ref: SCHEDULED-TASK-HEALTH item below (doctor currently can't see this failure at all). **DISPOSITION (2026-07-12 overnight session, operator-prioritized): RESOLVED — root cause was NOT an environment delta in the script: the NL-session-resumer task did not exist on this machine at all (verified Get-ScheduledTask), and NL-workstreams-heartbeat pointed at MSYS paths (/usr/bin/bash) Task Scheduler cannot resolve (0x80070002 every 5 min). Fixed per the runbook wrapper pattern: state/task-wrappers/{run-hidden.vbs,resumer-tick.cmd,heartbeat-tick.cmd}, resumer registered /SC MINUTE /MO 10, heartbeat action repointed. Both LastTaskResult=0; resumer tick-rc=0; supervisor-pass clean (15 seen/10 classified, liveness guard verified excluding a live session). Unarmed (shadow-equivalent) pending would-have-resumed review; arming tracked in NEEDS-YOU.**


- **JQ-WRITER-CLASS-AUDIT-01 — formal audit of remaining `jq`-writer call sites named in the NL-FINDING candidate sweep** (added 2026-07-06 from nl-issue triage, branch `claude/dreamy-mclaren-6f2ac3` class-sweep note; label: `harness-gap`, `priority:low`). The `session-resumer.sh` jq-failure-truncation bug (fixed on master, commit `fbbfc19`) prompted a broader sweep for the same failure shape (`command -v jq` proves PATH-resolution only, not invocation success; a subsequent `|| true` can silently swallow a failed jq write). Three durable-state writers were named as candidates: `adapters/claude-code/hooks/workstreams-orchestrator-queue.sh:44`, `adapters/claude-code/hooks/workstreams-extract-pending.sh:317-376`, `adapters/claude-code/scripts/dispatch-ci-watcher.sh:182`. **Manual inspection this session (not a full self-test audit):** none of the three exhibit the vulnerable shape as currently written — `workstreams-orchestrator-queue.sh:44` captures jq's own exit status via `||` and re-writes via `printf` on failure (safe); `dispatch-ci-watcher.sh:182` uses the `jq ... > "$tmp" && mv "$tmp" "$state_file"` temp-file-then-atomic-move pattern (a failed jq leaves `$tmp` unmoved, original file untouched — safe); `workstreams-extract-pending.sh`'s jq calls pipe into a sibling emit script via stdin (`|| true` swallows failure but there's no direct state-file truncation to lose). **Remaining work:** this was a manual read, not a fixture-proven audit — turn it into an actual self-test scenario per file (broken-jq-stub fixture, same Scenario-14 pattern as the resumer fix) so the "safe" verdict is proven, not eyeballed, and so future edits to these call sites can't silently reintroduce the bug. `signal-ledger.sh`'s `ledger_emit` is confirmed NOT affected (pure-bash escape, no jq branch — no work needed there).

- **WINDOWS-EOL-LF-CHECKLIST-01 — no doctrine/checklist line for "Windows-authored repos need an `eol=lf` `.gitattributes` at creation"** (added 2026-07-06 from nl-issue triage; label: `harness-gap`, `priority:low`). **Class.** Any repo authored on a Windows box with `git config --global core.autocrlf true` (this machine's setting) is one file-edit-and-commit away from mass CRLF conversion across the whole tree, unless a `.gitattributes` pinning `* text=auto eol=lf` (or equivalent) is added at repo creation. Neural Lace itself hit this and was fixed (NL-FINDING-038/039, commit `3163e4c` — `.gitattributes` eol=lf pins + a doctor line-endings check + self-test fixture repair). **Gap.** The fix is NL-specific; there is no standing doctrine/checklist line generalizing it to other dev roots on this machine (or to repos created in future sessions). **Fix:** add a one-line checklist item — "new repo on a Windows box → add `.gitattributes` with `eol=lf` before the first substantive commit" — to the relevant harness-dev or git doctrine compact, plus (optional, lower priority) a one-time sweep of other active dev roots on this machine for the same exposure.

- **SECRET-SCAN-CI-BACKSTOP-01 — CI-side secret/denylist scan as defense-in-depth behind the local pre-push hook** (added 2026-07-06, F.3 decision 2; `priority:medium`). `git push --no-verify` bypasses local pre-push scanning by git design (documented, honesty_rationale in manifest; §9 forbids agents using it without operator say-so). Add a CI job scanning pushed diffs for credential patterns + the hygiene denylist so a bypassed local scan cannot ship a secret to the remote. Oracle: seeded fixture secret in a test branch -> CI RED. **Resolved (2026-07-12) — merged to master `f25132a`; plan closed and archived (`docs/plans/archive/secret-scan-ci-backstop-skip.md`).** Implemented on branch `secret-scan-ci-backstop-01` — new `.github/workflows/secret-backstop.yml` re-invokes the EXISTING `pre-push-scan.sh` (credential patterns) + `harness-hygiene-scan.sh` (denylist, `adapters/claude-code/patterns/harness-denylist.txt`) against the push/PR diff range, no pattern-list fork (provenance documented in the workflow header); deliberately additive to `server-side-enforcement.yml`'s pre-existing identical-script jobs (own named required-status-check surface per the entry's explicit ask, not a replacement). Oracle proven LOCALLY (Actions cannot run live from this environment) via new `adapters/claude-code/tests/secret-backstop-fixture-check.sh` — 3/3 scenarios PASS (planted AWS-key-shaped fixture -> pre-push-scan.sh exit 1 naming the file; clean diff -> exit 0; denylist-token fixture -> harness-hygiene-scan.sh exit 1). Workflow YAML structurally validated via `npx js-yaml`. `manifest.json` `secret-hygiene-prepush` entry's `waiver_path` updated from "OPEN QUESTION" to the F.3 ACCEPT-DOCUMENTED resolution + cross-ref; new sibling `secret-scan-ci-backstop` manifest entry added (same `events:["manual"]` CI-workflow convention as `synthetic-runner-ci`). Design-skip plan: `docs/plans/secret-scan-ci-backstop-skip.md`. Merge to master done (`f25132a`). Remaining for the operator: wire the new check into GitHub branch-protection required-status-checks (repo-admin action, outside repo-content scope).

- **PR-TEMPLATE-CRLF-01 — template validator false-fails CRLF PR bodies; CI reruns validate the frozen creation-time payload (NL-FINDING-030)** (added 2026-07-03 from PR #80 landing friction; `priority:medium`). Fix set: (1) strip `\r` at the top of `validate_pr_body` in `.github/scripts/validate-pr-template.sh` — `find_section_heading` uses line-exact `grep -Fxq`, so any CRLF body (GitHub web-UI edits store `\r\n`; autocrlf-smudged `--body-file` uploads too) false-fails today, and MSYS grep/sed mask the `\r` on the authoring machine (diagnose with `od -c`); (2) both workflow jobs (`pr-template-check.yml`, `server-side-enforcement.yml` pr-template-redundancy) fetch body/title at run time via `gh pr view --json body,title` instead of `${{ github.event.pull_request.body }}` so job reruns see the current body. Enforcement surface → harness-reviewer required; add a CRLF-body-must-PASS scenario to the validator self-test. Evidence: NL-FINDING-030 (od-proven on PR #80, which needed 2 empty retrigger commits + an LF-normalized upload to land). Spun-off session chip: task_f72b0e9c.

- **SELFTEST-ORACLE-PIN-01 — hook self-tests resolve their oracle from ambient cwd instead of pinning canonical** (added 2026-07-03, harness-reviewer minor on the D.5-remediation diff; `priority:low`). pr-template-inline-gate.sh --self-test resolves REPO_ROOT primarily via `git rev-parse --show-toplevel` from cwd: run from inside a DIFFERENT repo that carries its own `.github/scripts/validate-pr-template.sh`, the self-test validates against that repo's (possibly version-skewed) validator — a misleading doctor RED or masked drift. Realistic invocations (NL checkout cwd; non-repo cwd → nl-paths config fallback) PROVEN correct (11/11 from both cwd classes). Hardening: in self-test mode prefer `nl_repo_root()` FIRST and cwd-git second (inverse of runtime precedence — each mode's semantics). Sweep: `rg -n "rev-parse --show-toplevel" adapters/claude-code/hooks/*.sh` — audit which uses sit inside --self-test blocks. Fold into E.10.

- **GOLDEN-EVAL-ENV-01 — credential-push-blocked.sh is unrunnable on machines with the global core.hooksPath** (added 2026-07-02, Wave-C pre-cutover battery; `priority:low`). The eval commits a fixture AWS key in a temp repo; on any machine with `git config --global core.hooksPath` → the harness git-hooks dispatcher, the machine-global pre-commit credential scan blocks the FIXTURE COMMIT before the eval's actual pre-push assertion runs (exit 1 with "COMMIT BLOCKED"). CI (no global hooksPath) passes — the eval is canonical there. PROVEN pre-existing: eval + pre-push-scan.sh + git-hooks dispatcher byte-identical to origin/master at failure time. Fix: the eval's fixture commit should use `git -c core.hooksPath=/dev/null commit` (scoped to the temp repo only) so the local machine's global hooks don't intercept its setup. (2026-07-03: the hooks-estate instance of this same class was swept via NL-FINDING-029 / PR #80 — 43 fixture sites now set `git config core.hooksPath ""` after `git init`; same pattern applies here, but note the eval WANTS the pre-push hook active for its actual assertion — suppress hooks only on the fixture-setup commit, not the push path under test.)

- **WS-UI-FOLLOWUPS-01 — Workstreams status-surface residuals (advocate UX flags + builder edges)** (added 2026-06-12 at closure of `docs/plans/workstreams-ui-status-surface-redesign-2026-06-11.md`; all 4 acceptance scenarios PASSED — these are non-blocking rough edges; label: `workstreams-ui`, `priority:medium`). From the runtime end-user-advocate pass + builder follow-ups:
  1. **Keyboard focus loss on tree toggle** — toggling a branch re-renders the tree and drops focus to `<body>` (~11 Tabs back to the twisty). Fix: restore focus to the equivalent twisty after re-render (same discipline the I5 overlay stack applies). `workstreams-ui/web/app.js` tree render path.
  2. **Validator-offline degraded mode is silent in the UI** — when zod/`decision-context-schema.js` is unavailable, the server fail-closes (everything gates "context incomplete") but only warns on stderr; the GUI shows a sea of "needs enrichment" with no explanation. Fix: a degraded-mode banner (pattern: the schema-too-new refuse banner). `server/server.js:40-99` + `web/app.js`.
  3. **Duplicate "My tasks" roots in live data** (`mytasks-root` pre-existing vs code's `mytasks-operator`) — duplicate cockpit rows once the operator adds a task. Needs a ONE-TIME operator-supervised data reconcile (archive/merge one root) on the real state file — deliberately NOT auto-done by the build (real-tracker mutation withheld).
  4. **Cockpit row proliferation** — every root `branch-opened` becomes a cockpit "project" row; transient one-off branches will pollute the cockpit over time. Needs a policy (grouping / archival / min-item threshold).
  5. **Builder edges (documented in the plan's evidence files):** promote-retry cross-version partial edge + retitle-after-edit dedup edge; legacy `snap.backlog` captures are promote-only (no edit/remove events exist — honest fix-forward limitation, badged in UI); `lib/workstreams-task-bridge.js:189-197` TaskCreate items carry no `_category`; fresh worktrees lack zod so the emit self-test exercises its inline floor (README install-note candidate).
  6. **State-path config on BOOK uses the in-repo fallback (added 2026-06-15).** Observed when relaunching the GUI: `~/.claude/workstreams-state-path.txt` is ABSENT on this machine, so `resolve-state-path.js` falls back to the in-repo `neural-lace/workstreams-ui/state/tree-state.json` (which DOES hold the operator's real ~130-item / 426-event tracker, so data is correct + the new UI renders against it). BUT the Workstreams-consolidation design (`workstreams-consolidation-2026-06-08`) intended a single CANONICAL state file pointed to by that pointer file. With the pointer absent, BOOK reads/writes the in-repo copy while another machine pointed at the coordination-clone canonical file would diverge — a cross-machine split-brain risk. **Confirm intended:** either (a) BOOK legitimately uses the in-repo file and the consolidation pointer was never meant for it, or (b) BOOK should get a `~/.claude/workstreams-state-path.txt` pointing at the canonical coordination-clone state so all machines share one tracker. Low urgency (single-machine operation today); surface before two-machine Workstreams operation resumes. Cross-ref: `state/resolve-state-path.js`, ADR 045/046, the duplicate-`mytasks-root` item (#3 above — likely the same split-state symptom).

- **WORKSTREAMS-UI-PURPOSE-AUDIT-01** (2026-07-02, P1): Operator verdict — the Conversations-Tree/Workstreams UI 'has failed completely' at its purpose (digestible operator information: context, links, decisions). Run a dedicated purpose-failure audit as its OWN effort (explicitly not part of nl-overhaul): what the operator actually needs vs what it shows; decide rebuild / repair / retire. Emit-side writers preserved meanwhile; the in-chat digest (nl-overhaul E.1) is the primary surface.

- **HARNESS-GAP-50 — `session-wrap.sh` Signal 3 transitively false-fires on cross-session merges (global 4h window + no retry-guard)** (added 2026-06-10; from discovery `docs/discoveries/2026-05-17-session-wrap-signal3-transitive-false-fire.md`, decided this date; label: `harness-gap`, `priority:medium`). `plans_touched_this_session()` (session-wrap.sh:107) is still a **global `git log --since="4 hours ago"` window over the whole repo**, not the current session's own commits — any session that merges master while ANY plan archival (even another session's unrelated harness-infra plan) sits in the 4h window is blocked at Stop demanding a Build-Doctrine-roadmap refresh it has no honest basis to make; observed re-firing ~15+ times (2026-05-17) with the only natural resolution being wall-clock expiry. `session-wrap.sh` is also NOT wired through `lib/stop-hook-retry-guard.sh`, so the 3-strike block→warn downgrade never engages. **Decided remediation (discovery recommendation A + C):** (A) scope `plans_touched_this_session()` to the session's own commits (anchor candidates: commits not reachable from origin/master at session start, or `@{push}..HEAD`; merges must not attribute pulled-in commits) — fixes the false attribution; (C) wire session-wrap.sh through the retry-guard so any future unresolvable signal downgrades after 3 retries instead of looping. Signals 5/6 share the same `$touched` dependency — fix the class, not the instance. Load-bearing Stop-hook script with extensive self-tests → dedicated session, not a triage side-fix. Cross-ref: ADR 027/028; `adapters/claude-code/scripts/session-wrap.sh`.

- **CROSS-MACHINE-COORD-RESIDUE-01 — coordination-layer residue from the superseded cross-machine plan (ADR + reconciler shared-claims wiring + overlap detection)** (added 2026-06-10; superseded from `docs/plans/archive/cross-machine-workstreams-coordination-2026-06-04.md`; label: `harness-gap`, `priority:medium`). The plan's ARCHITECTURE (per-host `tree-state/<host>.json` + GUI peer-merge `merge-peers.js` + origin badges) was superseded by the Misha-approved consolidation (single canonical `workstreams-coordination/state/tree-state.json`, confirmed live via `~/.claude/workstreams-state-path.txt`), but three coordination-layer pieces were neither built nor obsoleted: **(1) ADR for the coordination substrate** (why a separate private repo on the operator's personal account; git+SSH; assisted-first claims) — the unused `051` number gap in `docs/decisions/` is this unwritten ADR; **(2) reconciler shared-claims wiring** — `workstreams-ui/state/reconciler.js` still reads the v1 local-stub `~/.claude/state/orchestrator/claims.json` (reconciler-config.js `leaseTtlMin: 30`, "v1 local-stub"), NOT the coordination clone's `claims.json` that `coord-pull.sh` refreshes; the orchestrator-prime SKILL's "respect peer claims (the shared claims.json the reconciler reads)" instruction is therefore honored by convention only — the mechanism it cites does not exist yet (Rule 7 class); **(3) overlap/redundancy detection** (`coord-overlap-detect.sh` over `tasks/*.json` target fields) — never created. Re-engage when two-machine operation resumes in earnest (BOOK active) or when orchestrator-prime's claim-respect needs to become mechanical. Cross-ref: the supersession note in the archived plan; `8c2ac95` (coord-push/pull, shipped and in use).

- **HARNESS-GAP-51 — main checkout's foreign staged batch (master, ~40 files, 32+ commits behind origin) needs operator-supervised reconcile; it carried a stale REVERSION of `docs/failure-modes.md`** (added 2026-06-12; label: `harness-gap`, `priority:high`). Observed while fixing GAP-49: the main checkout sits on master with a large staged-but-uncommitted batch from prior cross-machine sessions (cross-ref the GAP-48 note "whose backlog entry is in-flight in the main checkout") while local master is 32+ commits behind origin/master. Two distinct hazards: **(1) stale-content damage** — the batch contained a staged reversion of `docs/failure-modes.md` that deleted the Decision-033 schema extensions AND entries FM-024..FM-031 (all ratified on origin/master); committing the batch as-is would have regressed the catalog. That one file was neutralized 2026-06-12 via `git restore --staged --worktree --source=HEAD -- docs/failure-modes.md` (the staged version was a strict content-subset of HEAD; nothing unique lost). The rest of the batch is UNAUDITED and may contain both genuinely-new in-flight work and more stale-copy damage. **(2) commit deadlock** — `scope-enforcement-gate.sh` correctly flags the batch's out-of-scope files on every `git commit` from the main checkout, so NO commit (even pathspec-limited) can pass there until the batch is dispositioned; this session routed around it via a clean worktree (the non-destructive path). **Remediation (operator-supervised — auto-resolving risks destroying in-flight work, FM-001 class):** per staged file, diff against origin/master — content already upstream → unstage/discard; genuinely new → commit under its owning plan; stale reversion (file OLDER than HEAD/origin) → restore from HEAD like the failure-modes case. Then `git pull --ff-only origin master` (or rebase per the configured defaults) once the tree is clean. Cross-ref: discovery `2026-06-09-scope-gate-uses-session-cwd-not-cd-target.md` option B (hook-sync stale-copy class — same shape, different surface). **DISPOSITION (2026-07-12 overnight session): RESOLVED — the foreign staged batch was audit-triaged per-file (docs/reviews/2026-07-12-overnight-state-audit.json): superseded content discarded (salvage copy kept), novel content landed at a8aab61, stale failure-modes.md reversion discarded; main checkout synced to master and the feat branch reconciled (pt 3ec1b21). Verified clean.**

- **HARNESS-GAP-48 — UX/CX review criterion not folded into `completion-criteria-gate.sh`** (added 2026-06-10; renumbered from 47 — that number is claimed by the scope-gate target-repo defect fixed in 8da2320, whose backlog entry is in-flight in the main checkout). P2. ADR 053's customer-facing-review gate ships as the sole mechanical enforcement of "UX agent + customer-advocate agent review attached" at session wrap. The original 2026-06-02 design also handed a 9th completion criterion off to the (then-uncommitted) completion-criteria gate via `.claude/state/spawned-task-results/`; that gate shipped (ADR 049) with its original eight criteria and the handoff was never reconciled. **Remediation:** add the UX/CX criterion (key e.g. `ux_cx_review`, N/A for backend-only work) to `completion-criteria-gate.sh`'s criteria set + template + rule `completion-criteria.md`, composing with (not replacing) `customer-facing-review-gate.sh` — one blocks at wrap on the specific UX/CX-missing condition; the other tracks it in the broader checklist. Cross-refs: `docs/decisions/053-customer-facing-review-gate.md` Landing note; `adapters/claude-code/rules/customer-facing-review.md` "Coordination with completion-criteria-gate".

- **HARNESS-GAP-46 — `isolation:"worktree"` Agent/Task spawns root the worktree in the launcher's cwd repo, not the dispatched task's target repo** (added 2026-06-03; label: `harness-gap`, `priority:low`). **Root cause.** The Agent tool's worktree isolation snapshots the *current session's* repo (the launcher's cwd) to build the isolated worktree; it has no notion of a target repo that is named only in the dispatch prompt. So a cross-repo dispatch — an orchestrator running in repo A dispatching a builder to work on repo B — gets a worktree rooted in A, the wrong tree. **Impact.** Cross-repo dispatches get the wrong worktree root; builders must self-detect their cwd and self-create a worktree off the target checkout; without that workaround a downstream-product artifact (product/person names) can land in the harness repo and trip the `harness-hygiene-scan.sh` denylist (or harness content can leak into the product repo). Observed twice in a 2026-06-02 neural-lace orchestrator session dispatching builders against a downstream product repo. **Interim mitigation (already in practice).** Orchestrator dispatch prompts instruct cross-repo builders to (1) `pwd`-detect their root and (2) if not in the target repo, `gh auth switch` to the target's account, `cd` the real target checkout, `git fetch`, and `git worktree add` their own isolated worktree off the target branch — then do all work there. **Proposed fix.** (a) Codify the convention in `orchestrator-pattern.md` — DONE 2026-06-03 (new "Cross-repo worktree dispatch" sub-section; this PR). (b) Optional mechanism: extend `teammate-spawn-validator.sh` to **WARN (not block)** when an Agent worktree-spawn's prompt references a repo path different from the launcher's cwd repo, surfacing the rooting caveat at spawn time. Cross-ref: `adapters/claude-code/rules/orchestrator-pattern.md` ("Cross-repo worktree dispatch"); `adapters/claude-code/hooks/teammate-spawn-validator.sh` (proposed warning).

- **HARNESS-GAP-45 — anti-vaporware policy doesn't cover CONFIG CONTROLS (toggles/flags/settings that render but don't change behavior)** (added 2026-06-03; label: `harness-gap`, `priority:high`; **disposition: COMPLETED 2026-07-13 → plan archived at `docs/plans/archive/vaporware-config-controls.md` (8/8 task-verifier PASS, harness-reviewer round-2 PASS, close commit 735fe66; decorative config controls now a named, checked vaporware class: doctrine compact + -full companion, planning FOC clause, functionality-verifier Config-control protocol, functionality-auditor registry-vs-callsite sweep, FM-038, manifest pattern row)**). **Originating case (Misha-flagged 2026-06-03):** the downstream product's per-org permissions matrix had **6 of 16 toggles decorative** — `team.invite`, `team.role.change`, `team.force_logout`, `costs.view`, `alerts.config.edit`, `contact.delete` render as configurable matrix cells but are actually governed by hardcoded role checks (or nothing), so toggling them has NO effect. The actions work + are access-controlled (via hardcoded `caller.role` guards), but the matrix — the framework's own RBAC admin surface — lies. Misha: "this is something the anti-vaporware policy should have caught." He's right. **Root cause.** The anti-vaporware gates (`functionality-verifier`, `wire-check-gate`, runtime-verification) verify what a builder DECLARES per-PR; a config control slips because (a) nobody declares "toggling X changes behavior" as a runtime-verification scenario, and (b) shadow-mode is a legitimate rollout state that simply never got flipped to enforce. There is no STANDING INVARIANT asserting that a registry entry (permission / feature-flag / event-type) is actually wired to enforcement. This is a FUNCTIONALITY-OVER-COMPONENTS failure class: the control component exists, compiles, and renders, but the user-observable functionality (toggle → behavior change) is absent. **Proposed fix (harness-level).** (1) `planning.md` FUNCTIONALITY-OVER-COMPONENTS — add an explicit clause: a configurable control (permission toggle, feature flag, setting, dropdown) is "done" only when *changing it is proven to change observable behavior*, not when it renders; a control wired to nothing (or to shadow-mode) is vaporware. (2) `functionality-verifier` rubric — add a "config-control" check: exercise the control by changing it and observing the behavioral effect at the governed surface. (3) Generalizable **registry-vs-callsite invariant** pattern: any code maintaining a registry of capabilities + a separate UI to configure them should have a mechanical check that every registry entry is wired to enforcement (the downstream product's project-level instance: extend `check-permission-drift.ts` to fail on any `PermissionId` with no enforce-mode call site — being built under the downstream product #437). (4) New `FM-NNN` failure-mode entry: `vaporware-config-control` (a configurable control that renders but does not change behavior). **Cross-ref.** the downstream product #437 (the originating fix — make every permission toggle effective + the project-level decorative-cell detector); `~/.claude/orchestrator-prime/permission-toggle-effectiveness-2026-06-03.md` (full capture). Effort: ~3-4h (policy edits + rubric + failure-mode; the generic invariant-pattern doc is the larger piece).

- **AUTO-INSTALL-V2 — widen synced surfaces + prune + backup-dir hygiene** (added 2026-06-02). P2. Follow-up to ADR 048 / `session-start-auto-install.sh` (the cross-machine propagation gap — formerly the HARNESS-GAP-44 install-footgun family — is now ADDRESSED for executable surfaces). v1 deliberately scoped to `hooks/` + `scripts/` + `settings.json` wiring. v2 candidates: (1) widen the synced directory set to `rules/`/`agents/`/`templates/`/`docs/` (these degrade gracefully when slightly stale, so lower priority, but a stale rule still misguides the model); (2) PRUNE live files removed from canonical (v1 is additive/update-only — a hook deleted upstream lingers in live until a full `install.sh`); pruning needs a safe-delete policy that won't remove an intentionally-kept local file; (3) prune accumulated `.backup-auto-install-<ts>/` dirs (install.sh's `prune_stale_backups` matches `.backup-YYYYMMDD-HHMMSS` only, NOT the `auto-install` prefix, so these accumulate — add a >30-day sweep matching the hook's own prefix). Risk: low (all reversible). Effort: ~2-3h.
- **COMPLETION-AUDIT-DEPTH-DOWNSTREAM-01 — Per-feature doc-DEPTH gaps in downstream support docs (C-47 transfer flow + Smart Import enhancements under-documented)** (added 2026-06-01; label: `product-doc`, `priority:medium`; **belongs in downstream's backlog — filed here because this neural-lace session must not commit into the downstream repo while a parallel downstream doc-tier session is active; migrate on next downstream session**). **Now mechanically surfaceable:** the redesigned Part B (`page-doc-accuracy-audit.sh`, see `docs/audit/page-doc-accuracy-2026-06-01.md`) flags exactly this class going forward as 🟡 UNDOCUMENTED (page section the doc doesn't cover) — the baseline downstream run found 73 such sections across 25 pages. **Finding (honest, evidence-grounded).** Page-level doc coverage is COMPLETE (every contractor-facing page has a `docs/support/*.mdx` — 0 MISSING_DOC, 0 STALE), so the "shipped without ANY user docs" premise is REFUTED at the page level; the in-flight doc work built page-level coverage. BUT file-existence ≠ flow-coverage-depth: `docs/support/contacts.mdx` covers bulk import in a single generic line ("Import contacts in bulk from a CSV export… Settings → Import") and does **not** document (a) the **C-47 consent-transfer flow** (move-contact / accept-transfer / consent-email behaviors shipped via PRs #395/#413) or (b) the **Smart Import** column-mapping / name-parsing / error-reporting enhancements (C-09/C-10/C-11/C-12/C-15/C-48). `whats-new.mdx` (S7) and the Twilio docs (`calls.mdx`, `phone-assistant.mdx`) DO appear substantively covered; F4 Platform Console maps to platform-owned pages (`admin-platform-analytics.mdx` exists; not contractor-facing per criterion #4). **Proposed fix (downstream doc session's scope — NOT this session's, per the build directive).** Enrich `contacts.mdx` (and/or a settings/import doc) to cover the C-47 transfer flow and the Smart Import enhancements as shipped. Cross-ref: ADR 049, `rules/completion-criteria.md`, the project-tier user-doc gate session.

- **COMPLETION-AUDIT-GRANULARITY-01 — page-vs-doc per-page flow coverage (residual after the Part B redesign)** (added 2026-06-01; **LARGELY SUPERSEDED same-day** by the Part B redesign — `page-doc-accuracy-audit.sh` now does forward-facing per-page page-vs-doc coverage: STALE = doc names UI absent from `src/`, UNDOCUMENTED = page section heading the doc never mentions; label: `harness-gap`, `priority:low`). **What shipped (resolves the core of this item):** the audit checks each live contractor-facing page's support doc against the page's current headings + bold doc-term references — the "page has a doc but the doc doesn't cover what the page does" gap is now mechanically surfaced (73 UNDOCUMENTED page sections on the baseline downstream run). **Residual (not yet built):** (1) **BEHAVIOR_MISMATCH** — "click X to Y" where the code shows X does Z (deferred; too low-precision for static v1). (2) **Stub/thinness detection** — flag `doc_path` files below a byte/line floor or with placeholder markers (compose with F7's stub definition). (3) **Runtime mode** — Playwright against the deployed app to catch dynamic content static analysis misses. (4) UNDOCUMENTED is heading-only (button labels were too noisy); a future pass could add high-precision button-label coverage. Cross-ref: ADR 049, `page-doc-accuracy-audit.sh`.

- **HARNESS-HYGIENE-STALE-PLANS-01 — [CLOSED 2026-07-02] One-time archival sweep of 24 chronically-`Status: ACTIVE` plans that cross-block unrelated sessions via `scope-enforcement-gate.sh`** (added 2026-06-01; label: `harness-gap`, `priority:medium`). **Evidence of closure:** `grep -l "^Status: ACTIVE" docs/plans/*.md | wc -l` now returns 7 top-level ACTIVE plans (down from the 24-of-37 verified 2026-06-01), via the incremental triage sweeps recorded in the backlog changelog (v53–v58) plus `docs/plans/triage-stale-plans-2026-06-17.md`; the acute cross-blocking rot this item tracked is resolved. **Root cause (historical).** Verified 2026-06-01: 24 of 37 top-level plan files in `docs/plans/` carry `Status: ACTIVE`. `scope-enforcement-gate.sh` iterates *every* ACTIVE plan and blocks any `git commit` touching a file outside that plan's declared `## Files to Modify/Create` (or `## In-flight scope updates`) sections — so a session doing unrelated work gets blocked against plans it has nothing to do with. The gate is correct; the rot is the 24 stale plans that were never flipped to a terminal status and archived. This is the **HARNESS-GAP-29 / GAP-30 / GAP-31 (plan-staleness) family manifesting in practice** — those propose *preventive* mechanisms (SessionStart surfacer / ready-to-close detector / waiver-density alarm); none performs the one-time remediation of the 24 that already exist. **Proposed fix (historical).** (1) A one-time triage sweep classifying each of the 24 as *truly-active* / *abandoned* / *completed-but-not-archived*, then flipping `Status:` + archiving the latter two via the existing `plan-lifecycle.sh` archival path. (2) Optionally land a Stop-hook (or extend the GAP-29 SessionStart surfacer into) a plan-staleness gate that prevents a plan sitting ACTIVE beyond N days without a checkbox flip or an explicit waiver, so the backlog of stale ACTIVE plans cannot re-accumulate. Cross-ref: GAP-29/30/31 (the preventive half), `scope-enforcement-gate.sh`.

- **GH-AUTH-AUTOSWITCH-WORKORG-01 — `gh` active identity auto-switches to the work-org account on push, breaking `gh pr merge` on the personal-account remotes** (added 2026-06-01; label: `harness-gap`, `priority:medium`; the operator's proposed handle baked in the work-org account name, scrubbed here per harness-hygiene — concept search handles: "gh auth switch", "pr merge perms"). **Root cause.** On every `git push` something (a push-time hook or `gh`/`git` config — likely the SessionStart account-switcher reading `~/.claude/local/accounts.config.json`) flips the active `gh` identity to the work-org (PT) account, which lacks merge permission on the personal-account remotes. Result: each `gh pr merge` requires a manual `gh auth switch` back to the personal account first. **This is distinct from HARNESS-GAP-12 (IMPLEMENTED 2026-05-04).** GAP-12 fixed *pushes reaching both remotes* via SSH multi-push — SSH key auth bypasses the gh-active-account dependency entirely. But `gh pr merge` uses the `gh` REST API, which still keys off the *active gh CLI identity*; SSH keys don't touch it, so the merge path was never covered by GAP-12's fix. **Proposed fix.** Identify the exact hook/config doing the push-time auto-switch and either (a) pin the merge-capable identity per-repo, or (b) drop the push-time switch (pushes already auth via SSH keys, so the switch buys nothing for neural-lace). Rotate the merge-identity expectation to whichever account holds merge perms across all repos (the personal account). Cross-ref: GAP-12 (the push half, solved via SSH multi-push). **SCHEDULED 2026-07-07** (operator disposition, O.9 acceptance round-trip — operator: "This one simple, stupid little thing wastes a lot of time... incorporate this into the work being done"): building now on branch `build/gh-account-autoswitch` — a PreToolUse Bash hook that auto-`gh auth switch`es to the target remote's owner before `gh pr merge`/`create`/`push`, so the agent never stops to wait. Row closes DONE when that merges. This 36-day fester is the golden anti-pattern driving the O.9 build-escalation enhancement (`build/backlog-build-escalation`).

- **PT-FORK-SYNC-NOT-RUNNING-01 — work-org (PT) fork mirrors drift after master merges; `sync-pt-to-personal.sh` not firing on schedule / incomplete coverage** (added 2026-06-01; label: `harness-gap`, `priority:medium`). **Root cause.** The personal-account ↔ work-org (PT) mirror repos fall out of sync after master merges. `sync-pt-to-personal.sh` (`adapters/claude-code/scripts/sync-pt-to-personal.sh`, added v47 / 2026-05-31) is the intended propagation mechanism, but it appears not to fire on a schedule and/or not to cover all repos — so a merge lands on one fork while its mirror stays stale. **Proposed fix.** Audit (1) when `sync-pt-to-personal.sh` last ran, (2) which repos it covers, and (3) whether it is wired to a cron / Windows scheduled-task or invoked only manually. If unwired, wire it (per-merge trigger or a cadence). If wired, diagnose why these specific merges did not propagate (coverage gap, auth failure, or a silent error swallowed by the script). Cross-ref: `adapters/claude-code/scripts/sync-pt-to-personal.sh`; the v47 git-best-practices initiative that introduced it. **Live evidence (2026-06-01).** Filing this very item produced the symptom: `git push origin master` reached the personal remote (fast-forward) but the work-org remote *rejected* it non-fast-forward. Inspection showed the two forks deeply diverged — the work-org tip carries ~10 commits the personal/local side lacks (the hygiene-2 + git-best-practices PRs `#49`–`#57`), and the personal side carries ~10 commits the work-org lacks (the decision-context-gate + pr-health-snapshot + f7-doc-gate arc, PRs `#45`–`#48`); the two master trees are different hashes. So the drift is not a one-commit skew — `sync-pt-to-personal.sh` has not propagated either direction across at least two recent PR waves. Reconciling divergent ~10-commit histories on a dual-hosted repo is Tier-3 (not an autonomous action); needs operator-driven reconciliation + a working sync cadence. **DISPOSITION (2026-07-12): FOLD → docs/plans/master-drift-autocorrection-2026-07.md — same failure class (mirrors drift after one-sided master merges).** **RESOLVED (2026-07-13): that plan is BUILT + SHIPPED + LIVE + closed/archived** — `adapters/claude-code/scripts/master-drift-autocorrect.sh` now FF-syncs a strictly-behind master via a dedicated clone on every session start (no tokens, never force); true divergence is surfaced for a reviewed merge, never auto-merged. Corrector self-test 12/12, git-freshness hook 15/15, harness-reviewed (CONDITIONAL-PASS → all 6 findings fixed). This is the auto-correction cadence this row asked for. Residual (separate, filed): `sync-pt-to-personal.sh` shares a latent push-URL discovery bug — its own nl-issue.

- **HARNESS-GAP-42 — `hooks-selftest.yml` never installs `conversation-tree-ui` node deps, so every node-dependent conv-tree hook fails cold in CI** (added 2026-06-01). **(absorbed by docs/plans/nl-overhaul-program-2026-07.md — E.4 CI substrate)** P2.

  **Problem.** The `Hooks self-test` workflow (`.github/workflows/hooks-selftest.yml`) runs `bash <hook> --self-test` after a bare `actions/checkout@v5` with **no `setup-node` / `npm ci` step**. Four conv-tree hooks emit/validate through the `conversation-tree-ui/state/state.js` facade + `decision-context-schema.js` Zod module via `node -e require(...)`; that `require` needs `conversation-tree-ui/node_modules` (zod). In CI it throws, and each hook's writer-hook discipline silently exits 0 (state file never written; cross-field validation never runs) — so the node-path self-test scenarios FAIL cold while passing 29/29 locally (where `node_modules` is present from prior UI work). The growing `KNOWN_FAILING_HOOKS` allowlist is the symptom: `conversation-tree-emit.sh`, `conversation-tree-extract-pending.sh`, `conv-tree-emit-reconciler.sh`, and now `decision-context-gate.sh` (added 2026-06-01) are all the same class — node-dependent hooks the workflow structurally cannot exercise.

  **Evidence.** `decision-context-gate.sh --self-test` → 29/29 PASS locally, 20/29 in CI (run `26721762815`); the 6 cold-CI failures (ST2/ST5/ST11/ST12/ST28) are exactly the `state.js`-facade-emit + Zod cross-field-validation scenarios. ST5 tell: cross-field violation returned exit 0 with empty stderr instead of exit 2 — the Zod validator silently no-op'd because `require('zod')` failed. Gate source line ~240: `try { s = require(libPath); } catch (e) { ...; process.exit(0); }`. PR #45 (decision-context substrate, merged 2026-05-31) shipped the hook without adding it to the allowlist → turned master's `Hooks self-test` red. Allowlisted 2026-06-01 (`fix/hooks-selftest-allowlist-decision-context-gate-2026-06-01`) to un-red master.

  **Proposed class-fix (design-mode CI change — warrants its own plan).** Add a `actions/setup-node` + `npm ci --prefix conversation-tree-ui` (or equivalent) step to `hooks-selftest.yml` before the self-test loop, so all four conv-tree node hooks are *genuinely* exercised in CI; then de-allowlist all four entries and let real failures surface. Risk to scope in the plan: (a) the two `extract-pending`/`emit-reconciler` hooks may have a *second* failure cause (accumulated-state dependence per the existing allowlist comment), so de-allowlisting must be verified per-hook, not assumed; (b) adding node setup increases CI wall-time on every PR + master push. Editing `.github/workflows/*.yml` is design-mode per `design-mode-planning.md` — write a Mode:design (or design-skip) plan + `systems-designer` pass before implementing. Until then the allowlist (this session's fix) holds master green.

- **HARNESS-GAP-39 — Detect hooks wired to MCP tools that never fire from cloud orchestrators (audit-log signature lint)** (added 2026-05-23). P2.

  **Problem.** A hook can be wired in `~/.claude/settings.json` matching an MCP tool name, ship to master, and silently never fire in production — because the MCP tool only ever runs in a cloud-orchestrator session (Dispatch / `claude --remote` / `/schedule` Routines), where local `~/.claude/` hooks are NOT loaded (per `~/.claude/rules/automation-modes.md` Mode 3 — cloud sessions inherit only project `.claude/` per Decision 011). The wiring passes plan-reviewer + harness-hygiene + every existing gate because the wiring is *structurally correct*; what's missing is empirical evidence that the hook ever fires from a real session. The intended workflow silently breaks; the operator only notices when the downstream artifact the hook was supposed to produce is absent (a missing GUI surface, a missing telemetry entry, a missing report-back). Diagnosis happens only after the end-user notices the absence.

  **Evidence — the canonical instance.** The conv-tree-auto-current fix (PRs #24/#25, master `02f3ad9` + `dbc1354`, 2026-05-22) discovered exactly this signature in `~/.claude/hooks/conversation-tree-emit.sh --on-spawn`:
  - Wired since 2026-05-18 in `adapters/claude-code/settings.json.template:244-250` (PreToolUse, matcher `mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task`).
  - Audit log `~/.claude/logs/conversation-tree-emit.log` has 1463 `--on-spawn` entries across 2026-05-18 through 2026-05-22.
  - **100% of those entries are self-test fixtures.** Every session ID matches the self-test pattern (`session=sess-st-NN`); every title matches a self-test fixture name (`"Hello mcp__ccd_session__spawn_task"`, `"Idem"`, `"NoSentinels"`, `"WithSentinel"`, `"Tiny"`, `"Branch Six"`, `"abc.123"`, `"worker-feat-y"`); every sink path is either `/tmp/tmp.*/st-NN.json` (self-test temp) or the production state file written by self-test runs (not by real spawns).
  - Zero production firings across 5+ calendar days despite the matcher firing on every Dispatch `spawn_task` invocation — because Dispatch runs in the cloud and never sees `~/.claude/settings.json`.
  - The downstream symptom: the conv-tree GUI showed a stale tree; the operator only diagnosed the root cause by going looking for the audit log and observing it was only ever fixture-populated.

  This is the second observed instance of the class. HARNESS-GAP-34 (`end-user-advocate` not dispatchable in the Dispatch environment) is the first: a mandated mechanism that doesn't actually exist in the runtime where Dispatch sessions execute. Both belong to the class **"harness mechanism wired for a runtime it cannot reach"** — different surface (hook vs agent registry), same root pattern (the wiring is paper-only in the environment where it matters).

  **Proposed lint behavior.** A periodic harness audit (composing with `/harness-review` or a dedicated `scripts/audit-hook-empirical-firings.sh`) that:

  1. **Reads `~/.claude/settings.json`** (and `adapters/claude-code/settings.json.template`) and extracts every hook command + its matcher pattern. Identifies hooks whose matcher mentions an MCP tool by name (`mcp__*`) — those are the candidates for the cloud-only blind spot. Local-tool hooks (`Edit`, `Write`, `Bash`, `Stop`, etc.) are not candidates because those tools fire from every session mode.
  2. **For each candidate hook**, attempts to find its audit log. Conventions: `~/.claude/logs/<hook-name>.log` (the established convention used by `conversation-tree-emit.sh`, `propagation-trigger-router.sh`, etc.) OR `~/.claude/state/<hook-name>/*.json` OR a manifest of "tools that only fire in cloud orchestrators" maintained per-MCP-server.
  3. **Classifies log entries** as self-test vs production. Heuristics:
     - **Self-test markers (any one suffices):** session ID matches `sess-st-\d+` / `selftest` / `test-` patterns; sink path under `/tmp/` or matches `*-selftest-*`; title field matches a known fixture-style pattern (single-word ALL-CAPS, "Hello <tool-name>", "Test N", etc.).
     - **Production markers:** session ID matches a real Anthropic session UUID shape (`[a-f0-9-]{36}`); sink path is a non-tmp absolute path; the entry corresponds to a real plan or commit traceable in git history.
  4. **Flags any candidate hook** with ≥ 14 calendar days of audit-log entries where 0 production firings have been observed. Default window: 14 days (long enough that real Dispatch use should have triggered it; short enough that newly-wired hooks during shakedown are not falsely flagged).
  5. **Output format** mirrors `analyze-propagation-audit-log.sh` (categorical subcommands: `summary` / `suspicious-wirings` / `production-firings-by-hook`). Findings are advisory — the lint does NOT block, since "hook only fires in cloud" is occasionally legitimate (the hook is paired with a project `.claude/` mirror per Decision 011 Approach A and is *meant* to fire from cloud where audit visibility is also cloud-side). The lint surfaces the candidate; the operator confirms whether the wiring is intentional or theater.

  **Implementation sketch.** Two-file shape, matches the propagation-engine precedent (Tranche 6a, 2026-05-06):
  - **Script: `adapters/claude-code/scripts/audit-hook-empirical-firings.sh`** — reads settings + audit logs, emits classification. `--self-test` covers: (a) matched-tool-with-self-test-only entries flagged, (b) matched-tool-with-production entries cleared, (c) local-tool hook ignored, (d) hook with no audit log surfaces as `unknown-coverage` (also worth flagging — silence is not absence), (e) ≤ 14-day-old hook in shakedown window not flagged.
  - **Skill extension: `~/.claude/skills/harness-review/SKILL.md` Check 14** — sweeps `audit-hook-empirical-firings.sh suspicious-wirings` and lists the candidates in the weekly review output. Composes with Check 12 (calibration roll-up) and Check 13 (Knowledge-Integration ritual). Pattern-class — Check 14 surfaces, the operator decides; no auto-block.
  - **Audit-log convention:** establish that every PreToolUse hook matching an MCP tool MUST write to `~/.claude/logs/<hook-name>.log` so this lint has a substrate to read. Hooks that already log here (`conversation-tree-emit.sh`, `propagation-trigger-router.sh`) are compliant; hooks that don't log at all are silently uncheckable and should be enumerated as a separate finding.

  **Out-of-scope notes.**
  - Real-time enforcement (blocking the wiring at commit time) is NOT proposed. The cloud-vs-local boundary is fluid (Decision 011 Approach A explicitly enables cloud sessions to inherit harness via project `.claude/` symlink/copy), so a hook wired only for cloud is legitimate when paired with the Approach A migration. The lint surfaces the candidate; the operator judges.
  - Generalizing to non-MCP-tool hooks (e.g., a `Stop` hook that never fires because the matcher regex is wrong) is a sibling concern — different signature, different lint. Out of scope here.
  - Cross-machine aggregation (does the same hook fire from another operator's machine?) is out of scope — the lint is per-machine because audit logs are per-machine.

  **Effort estimate.** ~3-4 hours: ~1 hour audit-log classification script + self-test, ~1 hour settings-parser to enumerate candidates, ~1 hour `/harness-review` Check 14 wiring, ~1 hour writing the audit-log-convention extension into `harness-architecture.md` + `harness-hygiene.md`.

  **Priority.** P2 — the conv-tree case was caught by operator observation in ~5 days; the lint would catch it in 14 days. The friction-saved-per-detection is moderate (one round of "why isn't this working?" debugging avoided per false-wiring case). Not P1 because the existing failure-mode is recoverable; not P3 because the class is provably recurring (2 instances in 2 weeks: GAP-34 + this one).

  **Companion to:** HARNESS-GAP-34 (sibling instance — `end-user-advocate` not dispatchable in Dispatch env). HARNESS-GAP-19 (propagation engine — provides the audit-log substrate this lint reads). Decision 011 (cloud-remote inheritance — names the boundary this lint sits at). `automation-modes.md` Mode 3 (the structural reason the wiring fails silently).

  **Class:** `harness-mechanism-wired-for-runtime-it-cannot-reach`. Candidate new `FM-NNN` in `docs/failure-modes.md` if/when this lint surfaces a third instance — the class is provably recurring.

- **HARNESS-GAP-40 — drift-backlog + harness-evaluator v2 followups (F1-F8 from `docs/reviews/2026-05-25-harness-self-eval.md` Section 8)** (added 2026-05-25, shipped v1 in PR #34). The first weekly packet's honesty audit surfaced 8 known v1 gaps in System 1 + System 2: **F1** `artifact_search` too narrow (high false-negative rate; v2 should add semantic / LLM-assisted search); **F2** `mine-misha-asked.sh` regex matches conversational fragments even with MIN_ASK_LEN=40 + conversational-prefix filter (v2 should add LLM-classify pass on borderline cases); **F3** harness-evaluator Section 5 ("own track record") is placeholder until 2+ packets exist; **F4** harness-evaluator Section 4.4 ("agents to watch") is heuristic-seeded, not data-driven — v2 should consume `.claude/state/calibration/<agent>.md` per `rules/calibration-loop.md`; **F5** no surfacing channel wired yet — v2 should integrate with Conv Tree GUI "Drift" panel once the auto-emit enforcement lands; **F6** project-scope filter is substring-match — v2 should use a project-mapping config file; **F7** scheduled-task wiring deferred to Misha's cadence preference (resolved in v2: daily cadence per 2026-05-25 directive — see GAP-42); **F8** branch-juggling during the build orphaned the plan-commit and required cherry-pick recovery — suggests the harness's branch-state model under autonomous-mode could benefit from session-tied branch locks (out of scope for the original v1 work; surfaced for separate harness-improvement triage). P2 each; collectively P1 because they constrain the systems' utility. Effort: F3 trivial (time-passes); F4 + F5 medium (~3-5h each); F1 + F2 medium (~3-5h each, may need LLM-API integration); F6 small (~1h); F7 zero (Misha sets cadence); F8 unscoped harness-internal.
- **NL-CTREE-006 — Conversation-Tree UI v1.5: replace `window.prompt()`/`confirm()` sub-flows with inline form UI** (added 2026-05-18, conversation-tree-ui-v1 Phase C/D build). P2. Six GUI sub-flows use `window.prompt()` (defer-with-time, dispute-note, add-cross-link, annotate, add-project, attach-context). Functional for a single-user localhost tracker in a real desktop browser (Misha's actual usage — verified working) and the underlying `POST /api/event` event paths are reducer/selftest-proven (14/0), but: (a) `prompt()` blocks any headless/automated verifier so those flows can't be exercised by `functionality-verifier`/`end-user-advocate` runtime automation, and (b) inline forms are better UX than modal prompts. **Remediation:** replace each `prompt()` call site in `neural-lace/conversation-tree-ui/web/app.js` with a small inline form (the backlog-capture form already in `index.html` is the pattern to mirror). **Effort:** S — ~2-3 hr (6 call sites + styling, the form scaffold pattern already exists). **Priority:** P2 — no data-loss, no user-facing defect in the real desktop-browser usage; it's a verifiability + polish gap. Surfaced + dispositioned in the conversation-tree-ui-v1 completion report (Known Issues §3).
- **HARNESS-GAP-34 — `end-user-advocate` agent not dispatchable in the Dispatch environment** (added 2026-05-15, **renumbered from 33 at the 2026-05-16 merge** — master's v36 had independently shipped a different GAP-33 = the `prd-validity-reviewer` provenance blind spot; this gap takes the next free number, 34. The discovery file `docs/discoveries/2026-05-15-end-user-advocate-not-dispatchable-in-dispatch-env.md` and the conversation-tree plan's UX-review section still say "GAP-33" internally; those references are swept to GAP-34 in the same merge commit). P1. Dispatching `subagent_type: "end-user-advocate"` returns `Agent type 'end-user-advocate' not found` (the runtime agent registry the Dispatch env loads does not expose it), even though `adapters/claude-code/agents/end-user-advocate.md` exists and `~/.claude/rules/planning.md` ("Mandatory: end-user-advocate review for every plan") + `~/.claude/rules/acceptance-scenarios.md` (plan-time Stage 1 + runtime Stage 3) + `product-acceptance-gate.sh` (Stop position 4, gates session end on its runtime PASS artifact) all treat it as required. **Impact:** the entire Gen-5 adversarial-observation acceptance loop — advertised as the harness's single biggest defense against shipping incomplete builds — is paper-only in the environment where Dispatch sessions actually run; the Stop gate either cannot enforce or enforces against an artifact no available agent can produce. Surfaced during the conversation-tree design-process demonstration (Phase-4 plan-time review attempt). Discovery file: `docs/discoveries/2026-05-15-end-user-advocate-not-dispatchable-in-dispatch-env.md`. **Workaround applied this session:** plan-time-advocate coverage checklist self-applied + gap surfaced loudly (no silent skip per acceptance-scenarios.md); `systems-designer` + `ux-designer` independently cross-checked scenario coverage as a partial substitute. **Remediation options:** (a) register `end-user-advocate` in the runtime agent registry the Dispatch env loads (preferred — restores the mandated mechanism); (b) if the exclusion is intentional, downgrade the mandate to "required where the agent is available" AND add an explicit env-capability probe that surfaces the absence at session start (loud), not only on dispatch-attempt (silent until tried) — and reconcile `product-acceptance-gate.sh` so it does not gate Stop on an unproducible artifact. **Priority:** P1 — a mandated, Stop-hook-gated mechanism that does not exist in the running environment is an integrity gap. **Composes with:** the acceptance-loop self-test (`tests/acceptance-loop-self-test.sh`) which should have a registry-presence assertion so this is caught mechanically, not by a design session noticing.
- **HARNESS-GAP-33 — `prd-validity-reviewer` cannot detect AI-synthesized convergence signals in an interactive-protocol artifact (provenance blind spot)** (added 2026-05-15, master). Surfaced from the 2026-05-15 PRD-intake incident codified in the new `interactive-process-fidelity.md` rule: a session ran the 6-stage guided PRD intake protocol (Stages A–F) autonomously from carry-forward Dispatch context, synthesizing the user's answers for every stage and self-closing OQ-9, then committed the PRD. `prd-validity-reviewer` returned PASS — correctly, because it reviews substance-shape (seven sections present, scenarios concrete, metrics measurable) and the *content* was fine. The defect was provenance, not content: no human ever supplied the convergence signals the protocol defines. The reviewer has no view onto "was a human the source of these answers." **Proposed extension (do NOT implement from this entry — design first):** add a provenance heuristic to `prd-validity-reviewer` (and/or a sibling PreToolUse Write check on `docs/prd.md`) that flags an artifact as provenance-suspect when ALL of: (i) the PRD's git authorship for the creating commit is the AI/agent identity, AND (ii) the only conversation transcript backing the artifact contains no user-authorization markers across the interactive stages (no user message between stage-surfacing and stage-closure; no explicit disposition reply for any open question), AND (iii) the protocol is one classified as interactive per `interactive-process-fidelity.md` (PRD intake Stages A–F is the canonical case). When flagged, the verdict is REFORMULATE with the specific message "interactive-protocol artifact has no user-convergence provenance — re-run the protocol surfacing each stage's question." **Open design questions:** (1) where do "user-authorization markers" live and how does the reviewer read them — transcript scan, an explicit per-stage `Surfaced to user: <ts>` annotation the protocol must write (mirrors planning.md's Decisions-Log convention), or a `.claude/state/` provenance log? An explicit annotation the protocol emits is the cleanest machine-readable signal and avoids brittle transcript parsing. (2) False-positive risk: a session where the user genuinely answered inline but the marker wasn't written would be flagged — the annotation approach makes the marker the contract, so "no marker = re-run" is correct, not a false positive. (3) Scope: PRD intake first; generalize to other interactive protocols (plan-time interface-impact decisions, discovery-protocol irreversible dispositions) only after the PRD case is proven. **Effort estimate:** M — ~3-5 hr if the annotation-contract approach is chosen (protocol must emit `Stage <X> surfaced-to-user: <ts>` markers; reviewer asserts presence) plus 4-5 self-test scenarios; larger if transcript-scan is attempted instead (brittle). **Priority:** P2 — the `interactive-process-fidelity.md` rule (Pattern) closes the behavioral gap now; this Mechanism is the structural backstop for when the Pattern drifts under autonomy pressure. **Companion to:** `interactive-process-fidelity.md` (the rule this gap backstops), `prd-validity.md` / `prd-validity-gate.sh` (the substance-shape gate explicitly noted as provenance-blind), `planning.md` "Plan-Time Decisions" `Surfaced to user:` annotation convention (the precedent for an explicit machine-readable authorization marker). **Class:** `ai-synthesized-convergence-signal-in-interactive-protocol` (candidate new `FM-NNN` in `docs/failure-modes.md` if it recurs).
- **HARNESS-GAP-32 — `close-plan.sh` retroactive friction on legacy plans whose evidence-of-completion lives in prose + git history, not structured `.evidence.json` artifacts** (added 2026-05-15). Surfaced when closing two ACTIVE-but-100%-done plans on a downstream project (`capacity-preset-ui-polish` and `team-rollout-documentation-package`), both authored 2026-05-12 — calendar-after Tranche B's structured-evidence substrate (shipped 2026-05-05) but using the legacy prose-evidence-block convention that pre-dated it. Both plans had: every `^- \[x\]` task checkbox flipped, every `## Definition of Done` checkbox flipped, completion reports appended to the plan body, and the work merged to master via PRs (#179, #180). `close-plan.sh close <slug>` BLOCKED both with `"missing structured .evidence.json per task"` because the substrate's `<plan-slug>-evidence/<task-id>.evidence.json` files were never authored — the prose evidence in the plan body was the substrate when the planner wrote it. The fallback path the gate's own header names ("Genuine emergencies use manual git ops (visible, several steps)") — direct `Status:` Edit triggering `plan-lifecycle.sh` PostToolUse auto-archive — worked cleanly but treats every legacy-plan closure as an "emergency," which it isn't. The retroactive friction is itself contributing to staleness: it's why these two plans sat ACTIVE long enough to bleed ~20 waivers/day each into unrelated sessions (see GAP-29/30/31). **Three remediation options (any one would close the gap; not exclusive):** (a) **Grandfather by authoring date.** Detect the plan file's git-creation date; if before Tranche B's substrate-availability cutoff (2026-05-05 or configurable per-project), fall back to checking the legacy prose-evidence path (`docs/plans/<slug>-evidence.md` OR inline prose-evidence blocks in the plan body) instead of structured artifacts. Self-test: legacy plan with prose evidence PASSES; new plan without structured evidence FAILS. (b) **Add `close-plan.sh --legacy` flag** that explicitly opts into the prose-evidence path with audit-logged justification at `.claude/state/close-plan-legacy-overrides.log` (one entry per use, naming plan + reason ≥ 30 chars). Friction-but-not-blocking; visible in audit. (c) **Document the manual-close path as the recognized escape for legacy plans** in `~/.claude/rules/planning.md` "Plan File Lifecycle" section — currently the path lives only in close-plan.sh's header comment, so operators must read script source to discover it. **Recommendation:** (a) is the cleanest because it's automatic and doesn't introduce an escape hatch the agent could reflexively reach for (per the "loud is not rare" principle that killed the `--force` flag). (b) is workable but adds an audit-logged escape hatch. (c) is the cheapest — documentation only. Could ship (a) + (c) together. **Effort estimate:** (a) ~2-3 hours including the date-detection + per-task prose-evidence parsing + 4-5 self-test scenarios; (b) ~1 hour; (c) ~30 min. **Priority:** P2 — friction not data-loss; the workaround (manual Edit) takes 30 seconds. **Composes with:** GAP-29/30 (which surface the plans needing closure; GAP-32 ensures the closure path is friction-proportionate). **Companion-inverse to:** the `--force` flag removal 2026-05-06 (which intentionally raised friction to prevent reflexive bypass). GAP-32 lowers friction for a legitimately-different case (legacy plans), not for vaporware closures.

- **HARNESS-GAP-29 — `plan-staleness-surfacer.sh` SessionStart hook surfacing the three plan-staleness archetypes with concrete next-actions** (added 2026-05-14). Surfaced from a downstream-project audit (2026-05-14): the project has 14 ACTIVE plans, four of which fit recognizable staleness archetypes that no existing hook surfaces. **Archetype A — work-shipped-but-Status-not-flipped:** two plans (`capacity-preset-ui-polish` and `team-rollout-documentation-package`) have 100% of `^- \[x\]` task checkboxes flipped AND 100% of `## Definition of Done` checkboxes flipped, but `Status:` is still `ACTIVE`. Each has accumulated ~20 cross-worktree waivers in 2 days because the gate fires at session-end of every unrelated session. **Archetype B — plan-filed-but-no-work:** a CI-coverage plan is 8 days old, has 18 unchecked tasks and 0 checked, and has zero commits referencing the plan slug or its `## Files to Modify/Create` paths since the plan-creation commit. 69 cross-worktree waivers accumulated. **Archetype C — chronic high-waiver:** the project's largest in-flight plan has accumulated 200 cross-worktree waivers; another long-running ACTIVE plan, 69. The waiver volume itself is a signal nobody reads. **Archetype D — DRAFT plans never advancing:** a 24-day-stale voice-integration DRAFT plan, plus a 23-day-stale consent-intake DRAFT blocked on a parent that may itself be done. **Proposed mechanism:** new SessionStart hook that iterates every plan in `docs/plans/*.md` (top-level only), computes for each: `task_completion_pct = checked / (checked + unchecked)`, `dod_completion_pct` (same for `## Definition of Done`), `days_since_last_commit_touching_plan` (via `git log -1 --format=%ct` on the plan file), `waiver_count` (cross-worktree count of `acceptance-waiver-<slug>-*.txt` matching this plan's slug across `git worktree list` outputs). Emit a system-reminder block listing plans matching any of: (A) `task_completion_pct == 100 AND dod_completion_pct == 100 AND status == ACTIVE` → "READY TO CLOSE: run `/close-plan <slug>`"; (B) `days_since_last_commit > 7 AND task_completion_pct == 0` → "STALLED: 0 work in 7+ days; abandon, defer, or restart"; (C) `waiver_count > 30 AND status == ACTIVE` → "HIGH WAIVER COUNT (N waivers); close, defer, or split"; (D) `status == DRAFT AND days_since_last_commit > 14` → "DRAFT 14+ days untouched; advance to ACTIVE or archive as SUPERSEDED". **Effort estimate:** ~3 hours including 6+ self-test scenarios (one per archetype + clean-no-stale-plans + multi-archetype-same-plan + zero-plans-edge-case). **Priority:** P1 — this addresses the highest-frequency operator-friction pattern Misha called out 2026-05-14 ("why are so many tasks going stale?"). **Risk:** low (SessionStart hooks are advisory; the surfacer cannot break sessions, only inform). **Composes with:** GAP-30 (close-eligibility detector at Stop) and GAP-31 (waiver-density alarm) — the three together close the staleness loop end-to-end. **Reverse-companion to:** the existing `plan-status-archival-sweep.sh` (which catches `Status: terminal` plans whose archive didn't fire) — this is the inverse: catches `Status: ACTIVE` plans whose close didn't fire.

- **HARNESS-GAP-30 — Extend `pre-stop-verifier.sh` with "ready-to-close" detector (Status: ACTIVE + all task boxes + all DoD boxes checked)** (added 2026-05-14). Companion to GAP-29. The existing `pre-stop-verifier.sh` (Stop hook position 1) catches the inverse problem mechanically: `Status: COMPLETED` with unchecked tasks (line 340), `Status: COMPLETED` with unchecked DoD bullets (line 650), `Status: COMPLETED` with failing DoD-artifact verification (line 831). The symmetric problem — `Status: ACTIVE` with EVERYTHING checked — is invisible. The downstream-project audit found 2 of 14 ACTIVE plans (`capacity-preset-ui-polish`, `team-rollout-documentation-package`) where every checkbox under `## Tasks` AND every checkbox under `## Definition of Done` is filled in, but Status was never flipped. Both plans now bleed waivers into every other session. **Proposed mechanism:** add a new check (e.g., Check 4d) that reads each ACTIVE plan in the working directory's `docs/plans/`, parses the task list and DoD section, and when `unchecked_tasks == 0 AND unchecked_dod == 0 AND status == ACTIVE`, emits a non-blocking system message: "Plan `<slug>` is ready to close (all tasks + all DoD items checked, Status: ACTIVE). Run `/close-plan <slug>` before session end to flip Status and trigger auto-archival." Non-blocking because: (a) sometimes the operator legitimately wants to keep ACTIVE for a final-review pass; (b) blocking would defeat the leverage moment — operator is at Stop with 30s of attention left. **Effort estimate:** ~1 hour including 3 self-test scenarios (ready-to-close-firing, ACTIVE-with-some-unchecked-not-firing, COMPLETED-with-everything-checked-not-firing). **Priority:** P1 — same root cause as GAP-29 but at a different lifecycle position (Stop vs SessionStart). **Risk:** very low (advisory only; uses existing `pre-stop-verifier.sh` plumbing). **Why both this AND GAP-29:** GAP-29 surfaces at session START so the operator picks up the cleanup at the top of their attention budget; GAP-30 surfaces at session END when the same session may have just finished work that completed the plan, with leverage to close in the same session. Together they double-tap the same condition at the two highest-leverage moments.

- **HARNESS-GAP-31 — `waiver-density-alarm.sh` SessionStart hook converting silent acceptance-waiver accumulation into a forcing function** (added 2026-05-14). **(absorbed by docs/plans/nl-overhaul-program-2026-07.md — E.3)** Surfaced from the downstream-project audit: cumulative 1369 `acceptance-waiver-*.txt` files exist across all 38 active worktrees on this single project. Top offenders (all anonymized; see audit notes for slugs): the project's largest in-flight plan 200 waivers, a since-closed support-agent plan 96 waivers (the 96 accumulated BEFORE someone finally flipped Status), a comprehensive-rebuild plan 69 waivers, a stalled CI-coverage plan 69 waivers, three since-closed plans at 60 waivers each (a scheduling default-fix, a journey-test-harness plan, an early-2026 roadmap plan). **The pattern is reproducible:** plans that should be closed accumulate 60-200 waivers before anyone notices. Each waiver represents a session that hit `product-acceptance-gate.sh` (Stop hook position 4), decided the blocking plan was unrelated to the current session's scope, wrote a one-line justification to a `.claude/state/acceptance-waiver-<slug>-<ts>.txt`, and exited. The waiver mechanism itself is legitimate (per `~/.claude/rules/acceptance-scenarios.md` and `git-discipline.md` Rule 3 — "write waivers, don't loop"). The gap: no mechanism reads the AGGREGATE waiver count per plan and surfaces it. **Proposed mechanism:** new SessionStart hook that runs `git worktree list --porcelain`, iterates each worktree's `.claude/state/acceptance-waiver-*.txt`, deduplicates by plan-slug (the slug is between `acceptance-waiver-` and the trailing timestamp), counts per slug, and emits: when any ACTIVE plan crosses a configurable threshold (suggested default: **30 waivers, ~10/day for 3 days**), surface "Plan `<slug>` has accumulated N waivers across worktrees (W7 distribution: …, oldest waiver: …). The waivers indicate every other session sees this plan as orthogonal to their scope. Three structural options: (a) close (work shipped — run `/close-plan <slug>`); (b) defer (work blocked — flip `Status: DEFERRED`); (c) split (scope too broad — decompose into smaller plans the gate can recognize as in-scope per-session)." **Effort estimate:** ~2-3 hours including the cross-worktree aggregation logic, threshold-tuning self-tests (4-5 scenarios: under-threshold-silent, at-threshold-warn, over-threshold-loud, multi-plan-multi-threshold, no-waivers-silent), and a flag to gate on `Status: ACTIVE` only (don't alarm on already-closed plans whose old waivers persist on disk). **Priority:** P1 — addresses the highest-volume signal Misha called out and is the most-load-bearing of the three GAPs because it surfaces structural problems (scope-too-broad plans) the other two GAPs cannot see. **Risk:** low (advisory only; threshold is configurable). **Composes with:** GAP-29 (which uses the same waiver-count signal as one of its four archetypes — but GAP-29 surfaces it as one of many, GAP-31 surfaces it loudly when it crosses threshold). **Companion to GAP-22** (escape-hatch sweep): GAP-22 asks whether escape hatches should exist at all; GAP-31 accepts they exist and surfaces aggregate usage as the alarm. Both can ship; they don't conflict. **Threshold rationale:** a project with 4-5 ACTIVE plans for ~5 days, each session triggering the gate on the 4 unrelated ACTIVE plans → ~20 waivers per plan per week is normal noise. 30+ in less time signals "this plan is irrelevant to the current work portfolio and should be closed or split." Tunable via `~/.claude/local/waiver-density-config.json` if needed.

- **HARNESS-GAP-28 — Dispatch spawner should set `CLAUDE_CODE_DISPATCH=1` env var so sessions can detect remote-Dispatch client mode** (added 2026-05-14). The `AskUserQuestion` / multiple-choice tool renders fine on standalone Claude Code clients (Desktop / IDE / terminal) but does NOT relay through remote-Dispatch clients (sessions spawned via `mcp__ccd_session_mgmt__start_code_task` where the user is on a phone, web UI, or another device). Under Dispatch, MC widget invocations block the session with no path forward. The rule (per `~/.claude/CLAUDE.md` Autonomy section, 2026-05-14 reshape) is now Dispatch-conditional: detect client mode, use plain text under Dispatch, MC widget OK standalone. **Current detection signal:** none reliable — investigation 2026-05-14 confirmed `CLAUDE_CODE_ENABLE_ASK_USER_QUESTION_TOOL=true` and `CLAUDE_CODE_ENTRYPOINT=claude-desktop` are BOTH set during confirmed Dispatch sessions, so neither distinguishes. **Proposed target convention:** the Dispatch spawner (start_code_task implementation in `mcp__ccd_session_mgmt` or wherever the orchestrator session-init lives) should inject `CLAUDE_CODE_DISPATCH=1` into the spawned session's environment. Interim fallback: users may set `~/.claude/local/dispatch-mode.json` (example at `adapters/claude-code/examples/dispatch-mode.example.json`) or signal in-conversation; agents default to standalone (MC widget OK) when no positive signal exists. **Effort estimate:** ~30 min (one-line env-injection edit in the spawner + a quick verification by spawning a Dispatch session and confirming `echo $CLAUDE_CODE_DISPATCH` returns `1`). **Priority:** P2 — operational papercut today; without it, the default-to-standalone fallback occasionally produces MC-widget invocations under Dispatch that block sessions. **Risk:** low (additive env injection, no existing behavior changes). **Related:** documented in CLAUDE.md Autonomy section under "Detection priority"; `dispatch-mode.json.example` template ships in `adapters/claude-code/examples/`.

- **HARNESS-GAP-27 — [SUPERSEDED 2026-05-27 by PR #26 / HARNESS-GAP-29] `scope-enforcement-gate.sh` blind to merge-commit semantics; option (a) lightweight migration-allowlist SHIPPED 2026-05-14; option (b) union-of-plans deferred per ADR 030** (added 2026-05-14, updated 2026-05-14, **superseded 2026-05-27**). **SUPERSEDED:** PR #26 (master `0d6bc43`, HARNESS-GAP-29) replaced the narrow migration-only merge exemption with an unconditional full-skip of the scope check whenever a rebase or merge is in progress — see `docs/plans/archive/scope-gate-rebase-exemption.md` + ADR 030 (now resolved). The blind-spot this entry tracked is closed; option (b) union-of-plans is no longer pursued (the full-skip is the chosen answer, operator-confirmed). Retained for history. Surfaced during a downstream-project PR-merge session (UX-audit follow-up work). The gate iterates ACTIVE plans currently visible in `docs/plans/*.md` and rejects any staged file not claimed by an active plan's `## Files to Modify/Create` section. When a feature branch merges master back in, master's concurrent commits pull in files from plans that were ACTIVE on master but are now archived (their parent plans got `Status: COMPLETED` and auto-archived to `docs/plans/archive/`). The gate doesn't see archived plans, so master's pulled-in files appear unclaimed, blocking the merge commit. **Today's workaround for non-migration files:** author a session-scope "merge-resolution plan" that wildcard-claims everything master might have touched (`docs/**`, `src/**`, project-specific subtrees, etc.). Fragile but workable. **Status of fix candidates:** (a) **Lightweight (SHIPPED 2026-05-14):** `_is_system_managed_path()` now honors a merge-context allowlist when `$(git rev-parse --git-dir)/MERGE_HEAD` exists. Currently allows `supabase/migrations/*.sql`, `prisma/migrations/**`, `db/migrations/**` — the commit-numbered migration paths master generates procedurally. 4 self-test scenarios added (s13-s16). Validates the highest-frequency failure case (PR #197). (b) **More general (DEFERRED, see ADR 030):** when MERGE_HEAD exists, check staged files against the UNION of all plans active on EITHER branch since the divergence point. Trigger to un-defer: 3+ distinct file classes beyond migrations require allowlist entries within a 30-day window, OR a merge-resolution-plan workaround takes >10 min for a single merge, OR a pilot project requests it as a structural blocker. (c) **Smallest (NOT YET shipped):** stderr documents the merge-resolution-plan pattern for non-migration cases. Could complement option (a) — captured here as a follow-up sub-task if recurrence justifies it. Priority: P3 now that option (a) is shipped (handles PR #197's specific failure shape).


- **HARNESS-GAP-19 — [CLOSED 2026-07-02]** — Wire `session-wrap.sh` into the Stop hook chain. **Evidence of closure:** `grep -n "session-wrap.sh refresh" adapters/claude-code/settings.json.template` matches (line ~536, `"command": "bash ~/.claude/scripts/session-wrap.sh refresh"`, wired as the final entry in the Stop hook chain) — the script is now auto-invoked at session end, no longer callable-by-hand-only. Historical: the script is built (`adapters/claude-code/scripts/session-wrap.sh`, 321 lines), self-tests 5/5 PASS, and ADR 027 v2 Layer 5 specifies it as the handoff-freshness mechanism — but it's currently callable by hand only, not auto-invoked at session end. Wiring it into the Stop chain (likely position 9, after the existing 8 narrative-integrity hooks) would make Layer 5 mechanical rather than discipline-only. Estimated effort: ~30 min (one settings.json.template edit + one live `~/.claude/settings.json` edit + a quick verification cycle). Recommended next-up after the Tranche 1.5 ship since the risk is small (script is idempotent + soft warnings) but the benefit is real (the orchestrator that wrote the rule was the same orchestrator that violated it). Added 2026-05-05.

- **`continuation-enforcer.sh` Stop-hook wiring gap** (surfaced via `adapters/claude-code/rules/session-end-protocol.md` "pending Wave D session-honesty-gate" marker; not previously tracked as a discrete backlog line — added here 2026-07-02 for reconciliation). **(absorbed by docs/plans/nl-overhaul-program-2026-07.md — D.3)** The hook exists and passes its own self-test but is not wired into the live Stop chain (`settings.json.template`); until wired, DONE/PAUSING/BLOCKED marker discipline is Pattern-only. D.3 supersedes this with `hooks/session-honesty-gate.sh` (the marker contract lands "live at last" per the master plan's D.3 task description).

- **HARNESS-GAP-23 — `review-finding-fix-gate.sh` reads stale `.git/COMMIT_EDITMSG` on `git commit -m` invocations** (added 2026-05-06). Surfaced during Tranche 5a authoring: the gate reads `.git/COMMIT_EDITMSG` to extract finding-ID tokens from the commit message, but on `git commit -m "..."` invocations git does NOT update `COMMIT_EDITMSG` until later in the commit cycle. Result: the gate matches against the PREVIOUS commit's message, producing false-positive blocks when the previous message contained tokens that match `<TAG>-NNN` and appeared in any review file. Reproduced 3 times in the 5a session: previous commit had token-shaped strings in its body (Tranche 6 decomposition), the next 3 commit attempts (with completely different messages, including an explicit `-F` invocation) were all blocked because the gate kept reading the stale prior message. Workaround used: write desired message to `.git/COMMIT_EDITMSG` first, then `git commit -F .git/COMMIT_EDITMSG`. Fix candidates: (a) gate sources message from `git log --format=%B HEAD@{1}` style introspection rather than the file; (b) gate explicitly handles the `-m` case by reading from environment vars git exposes during commit; (c) gate documents the workaround as a known limitation. Effort estimate: ~1-2 hours including self-test scenario for `-m`-after-tokenful-prior-commit. Priority: P2 (false positives are friction, not data loss). Risk: low (correctness-only fix). Companion to GAP-19 / GAP-22 family of "agent friction must be present-moment, not stale-state-from-prior-actions" patterns. **[Re-surfaced 2026-06-01 — alias `REVIEW-FINDING-FIX-GATE-COMMIT-EDITMSG-LAG-01`; not duplicated, this is the canonical entry.]** Cleaner fix angle than candidates (a)/(b): relocate the check out of the pre-commit/PreToolUse position (where `COMMIT_EDITMSG` holds the *prior* message) and into a `commit-msg` / `prepare-commit-msg` git hook, which is passed the in-flight message file path as `argv[1]` — or into a post-commit verification on `HEAD` that emits a *warning* rather than a hard block. Both read the actual staged message instead of introspecting reflog history, so they avoid the stale-file class entirely.

- **HARNESS-GAP-20 — Retrofit existing rules + agents from discipline form to mechanism form** (deferred 2026-05-06). **(absorbed by docs/plans/nl-overhaul-program-2026-07.md — program governance F.1)** Surfaced during the architecture-simplification arc when user asked "what else do we need to consider?" The pattern: many existing harness rules say "the LLM should do X at time Y." Convert those to: "a hook fires at time Y and does X mechanically." Examples of candidates:
  - `~/.claude/rules/orchestrator-pattern.md` "When to use orchestrator mode" — currently LLM-judges; could be a heuristic in a UserPromptSubmit hook that suggests dispatch when prompt resembles multi-task work.
  - `~/.claude/rules/planning.md` "Update SCRATCHPAD when plan status transitions" — currently LLM-discipline; converted to derived `state-summary.sh` per Path A this session, but the *rule itself* still says LLM should update SCRATCHPAD.
  - `~/.claude/rules/diagnosis.md` "After Every Failure: Encode the Fix" — discipline; could be a Stop hook that scans the session transcript for diagnosed-but-unencoded failures and surfaces them.
  - `~/.claude/rules/testing.md` various "must invoke X" disciplines — many candidates for auto-invocation hooks.
  - The 4 rules-vs-hooks splits already identified (acceptance-scenarios.md, agent-teams.md, design-mode-planning.md, testing.md) — partially captured separately.
  - Generally: every place a rule's body says "the agent must remember to..." is a candidate for mechanism conversion.
  Effort estimate: substantial (~5-10 hours of careful audit work plus per-conversion implementation; depending on how aggressively retrofitting, could be 20+ hours total). Priority: P2 — important but not blocking. Risk: low (retrofitting discipline → mechanism is structurally additive; original rules remain as documentation). Per ADR 026 ("harness catches up to doctrine") this is the long-tail of the catch-up; the architecture-simplification arc shipped the highest-leverage pieces, retrofit handles the residual. **Substantial context note:** the originating user observation 2026-05-06 was that even after Tranche 1.5 + Layer 5 + Signal 6, the orchestrator continues to make LLM-discipline-shaped fixes when blocked — every time a new failure mode surfaces, the agent's instinct is "add a rule the LLM follows" rather than "add a hook that fires automatically." The retrofit IS the systematic conversion of past LLM-discipline rules to current-best-practice mechanism form. Should NOT be conflated with new-rule-creation; the principle is "if the rule already exists, see if it can become a hook."

- **HARNESS-GAP-22 — Sweep harness for other escape-hatch flags / env-vars; remove or convert to non-LLM-satisfiable friction** (added 2026-05-06). **(absorbed by docs/plans/nl-overhaul-program-2026-07.md — program governance F.1)** Originated when user caught the `CLOSE_PLAN_EMERGENCY_OVERRIDE` env var I had added 2026-05-06 as a "removal of --force": *"I don't see how an env variable is any more friction to an agent than a --force flag... Just because it's loud doesn't make it rare."* Correct. Audit-logged escape hatches with rationale-length checks are not meaningfully more friction than `--force` for an LLM. Sweep candidates (non-exhaustive, per session memory): inline PreToolUse Bash blockers in `~/.claude/settings.json` already block git push --force, --no-verify, --no-gpg-sign — these are good (rejected outright, not gated). But various tooling commands the agent invokes through Bash may have --force flags that are NOT yet blocked: `git worktree remove --force`, `npm install --force`, `pip --force-reinstall`, `docker rm -f`, `git checkout --` (force-overwrite working tree), `git clean -fd`, `git reset --hard`. Each needs case-by-case judgment (worktree --force is legitimately needed when a builder crashed mid-state; npm --force is a code smell but sometimes warranted). Output: a documented inventory + rules for each. Effort estimate: ~3-5 hours of audit + per-flag judgment + selective hook additions. Priority: P2 once the immediate close-plan fix proves out. Risk: low (reversal trivial). Companion to GAP-20 (retrofit existing rules) and GAP-21 (deeper architectural review). Per the saved feedback memory `feedback_in_band_friction.md` (renamed 2026-05-28 from `feedback_loud_is_not_rare.md`), the principle is: agent friction must be present-moment, not consequence-deferred; "loud and audit-logged" are not friction.

- **HARNESS-GAP-21 — Deeper architectural review of the harness from automation-first lens** (deferred 2026-05-06). **(absorbed by docs/plans/nl-overhaul-program-2026-07.md — program governance F.1)** Surfaced when user asked "what else do we need to consider to resolve this once and for all?" The architecture-simplification arc (Tranche 1.5) addressed verification overhead by building deterministic procedures; the user's observation is that even with those procedures, the orchestrator continues to exhibit LLM-discipline-shaped failures (composing summaries while artifacts are stale, using `--force` escapes, building scripts that require manual invocation). The pattern suggests a deeper architectural review is warranted — not "fix this one gap" but "what does the cleanest-possible automation-first harness design look like, and how does the current harness compare?" Possible scope: (a) end-to-end audit of every harness component against the question "does this require LLM discipline or is it mechanical?", (b) systematic redesign of any LLM-authored artifact that the next session reads (every such artifact is at risk; the deeper redesign would replace each with a derived view + clearly-bounded LLM synthesis section), (c) re-examination of the rule + agent + hook inventory through the lens "what's the minimum LLM dependence we can have here?", (d) a refreshed roadmap that sequences the harness's own ongoing development under the automation-first principle, (e) examination of cases where Claude Code's hook event surface limits what's achievable (e.g., no PostMessage hook for verbal vaporware) and what workarounds exist. Effort estimate: substantial (~20-40 hours of focused review work + drafting + deep diff against current state). Priority: P1 once Path A from this session lands (HARNESS-GAP-19 + state-summary.sh + start-plan.sh + close-plan.sh `--force` removal). Risk: low; output is paper review + roadmap, not implementation. **Substantial context note:** this is the work the architecture-simplification arc was supposed to be, but Tranche 1.5 was scoped narrowly to the verification-overhead problem because that's what was acutely painful at the time. The user's repeated observation that the orchestrator keeps making LLM-discipline-shaped fixes suggests the principle was incompletely applied — a focused review would surface the long-tail systematically rather than discovering it gap-by-gap as failures occur. Run AFTER Path A's mechanisms have shipped + been operationally validated for at least one work cycle so the review has empirical evidence to reference, not just the existing inventory.

- **HARNESS-GAP-24 — Wire propagation engine into PostToolUse to surface real-time events** (added 2026-05-09, transferred from a downstream-project findings ledger as FINDING-036). Tranche 6a shipped the propagation engine (`propagation-trigger-router.sh` + `propagation-rules.json` + JSONL audit log at `build-doctrine/telemetry/propagation.jsonl`) but NOT the PostToolUse hook that would route real-time events to the engine. Consequence observed in a downstream project's Phase B work: dozens of qualifying events (plan-status flips, decisions-index edits, finding insertions, etc.) generated zero audit-log entries during the actual work because the engine fired only when invoked explicitly. The engine therefore cannot become a measurement substrate for KIT-6 until it's wired to fire on every relevant event. Fix candidates: (a) add a single PostToolUse hook entry in `settings.json.template` matching `Edit|Write|Bash` that pipes the event JSON to `propagation-trigger-router.sh`; (b) more selective per-tool matchers that route only events the engine's rule conditions can act on; (c) defer until Tranche 6b decision settles routing semantics. Per the originating finding: "Recommendation: defer to neural-lace Tranche 6b decision." Effort estimate: ~2-4 hours including self-test scenario for "PostToolUse fires → router invoked → audit-log entry written" + verification that no propagation rule has side effects beyond log-only in v1. Priority: P2 (gates KIT-6 mechanical firing; pre-pilot infrastructure complete except this). Risk: low (rules are log-only in v1; no behavioral change beyond audit-log volume). Companion to HARNESS-GAP-19 (session-wrap.sh wiring) — both are "scripts built but not auto-invoked."

- **HARNESS-GAP-25 — Profile + optimize slow propagation rules (`pt-proven-decisions-index-update`, `pt-proven-narrative-doc-staleness`)** (added 2026-05-09, transferred from a downstream-project findings ledger as FINDING-037). Both rules exceed 1s wall time per evaluation (flagged by `analyze-propagation-audit-log.sh slow`). With 16 events tolerable; at 1000 events/day = 30 min wall time per day spent in these two rules alone. Block on promotion: do NOT advance either rule from `log-only` to any blocking action until profiled. Both rules invoke `git log` style introspection; likely fixable by (a) caching the most-recent commit's metadata across rule invocations within a single router run, (b) replacing `git log` with cheaper `git rev-parse HEAD` + `git show --stat HEAD` calls where applicable, (c) lazy evaluation guarded behind cheaper preconditions, (d) parallel rule evaluation if profiling shows the bottleneck is sequential dispatch rather than per-rule cost. Effort estimate: ~3-5 hours including profiling instrumentation + rewrite + benchmark + self-test scenario asserting wall time under 200ms per rule. Priority: P2 (gates HARNESS-GAP-24's wiring — slow rules + per-event firing = 30min/day before optimization). Risk: low (rule semantics unchanged; correctness-only rewrite). Companion to HARNESS-GAP-24 (PostToolUse wiring); resolve in tandem.

- **HARNESS-GAP-26 — Build ADR cross-reference staleness analyzer for KIT-4** (added 2026-05-09, transferred from a downstream-project findings ledger as FINDING-038). KIT-4 (ADR cross-reference staleness) is one of the seven Knowledge-Integration Triggers in `build-doctrine/doctrine/07-knowledge-integration.md`; the `/harness-review` skill Check 13 sweeps each KIT trigger but KIT-4's analyzer is a stub. With 45 ADRs in `docs/decisions/` and 5 canon artifacts that should cross-reference them (architecture-overview, harness-architecture, doctrine principles/roles/gates, etc.), manual review is impractical. Fix: build `adapters/claude-code/scripts/analyze-adr-cross-references.sh` with subcommands matching the propagation-audit-log analyzer's pattern: `summary` (count of ADRs by referenced/unreferenced status), `stale` (ADRs whose last cross-ref edit predates their `Status:` change by N days), `orphans` (ADRs with zero cross-refs in canon docs). Output feeds `/harness-review` Check 13 KIT-4 row mechanically rather than as a "(pending analyzer)" stub. Effort estimate: ~4-6 hours including script + self-test scenarios + Check 13 wiring. Priority: P2 (Check 13 already exists with the row stubbed; building this graduates one of the seven KITs from manual-only to mechanical). Risk: low (read-only script, additive). Companion to Tranche 5a-integration's analyzer pattern (same shape as `analyze-propagation-audit-log.sh`).

- **HARNESS-GAP-08** — IMPLEMENTED 2026-05-05 via `docs/plans/archive/harness-gap-08-spawn-task-report-back.md`. spawn_task report-back convention shipped: rule, surfacer hook, settings wiring, vaporware-prevention map row, sync to ~/.claude/, multi-push to both remotes. 6/6 tasks PASS, 5/5 self-test scenarios PASS. Commits: `440a2d9`, `a7002e7`, `4627e01`, `343d5c6`, `606c70e`.
- **HARNESS-GAP-13** — IMPLEMENTED 2026-05-05 via `docs/plans/archive/harness-gap-13-hygiene-scan-expansion.md`. Full original 4-layer scope: denylist additions (Layer 1), heuristic detection (Layer 2 BLOCK), `/harness-review` skill extension (Layer 3), sanitization helper (Layer 4). 8/8 tasks PASS, 13/13 hygiene-scan self-test PASS, 5/5 sanitize self-test PASS, full-tree scan ZERO matches. Commits: `2a0488a`, `517b6b6`, `6e4672c`, `2371e97`, `e03d96b`, `606c70e`.
- **HARNESS-GAP-16** — ABSORBED 2026-05-05 into `docs/plans/harness-gap-16-closure-validation.md`. Building this session in parallel with Build Doctrine Tranche 0b per user directive 2026-05-05.
- **HARNESS-GAP-17 Part A** — User-facing narrative docs stale post-Build-Doctrine-integration (~3-5 hr doc sweep). **IMPLEMENTED 2026-05-05 (this session)** — see HARNESS-GAP-17 entry below for the per-doc summary. Part B (gate extension preventing recurrence, ~6-10 hr) remains DEFERRED per original P2 estimate.
- **HARNESS-GAP-14-followups** — IMPLEMENTED 2026-05-04 via Phase 1d-G (entry below preserved as the audit trail).
- **Rules-vs-hooks 4 remaining splits** (per Phase 1d-E-2 audit) — acceptance-scenarios.md, agent-teams.md, design-mode-planning.md, testing.md. Each is substantial restructuring per rule. Per Option B 2026-05-05, now eligible to dispatch via `spawn_task` with the new GAP-08 report-back convention.
- **Doctrine-migration codename discipline** — Surfaced 2026-05-05 during Tranche 0b parallel build; see `docs/discoveries/2026-05-05-doctrine-content-codenames-vs-hygiene-scanner.md`. Future doctrine migrations from `~/claude-projects/Build Doctrine/outputs/` (private repo, real codenames) into `build-doctrine/` (NL repo, harness-hygiene rules apply) must anonymize codenames to generic placeholders before commit. Heuristic-cluster check resolved via `is_path_shape_exempt()` extension (commit `b5cdccb`); denylist scan still applies and is correct. May not need a dedicated mechanism — the discovery file + this rule callout in harness-hygiene.md may be sufficient. Reassess if a future migration produces friction; otherwise treat as resolved-by-discipline.

- **PEER-VIEW-DENYLIST-COLLISION-01 — a peer machine's git branch name (or host name) containing a `GATE_HOOK_DENYLIST_PATTERNS` substring would 500 the entire cockpit landing payload** (added 2026-07-17 from cockpit-v2-push-materialized-store Task 4's own build; label: `harness-gap`, `priority:low`). **Root cause.** `server/peer-view.js`'s Task-4 "Peers" section renders a peer's raw git `branch` (and `host`) verbatim into `state_label`/`provenance_label`, which `server/payload-schema.js`'s `GATE_HOOK_DENYLIST_PATTERNS` anti-noise scan then walks over EVERY string in the landing payload — if a real branch happens to contain a token like `ask-registry`, `close-plan`, or anything matching `[a-z0-9_-]*-gate\b`, the WHOLE `GET /api/asks` response fails validation (500, diagnostics-only, never a leaking payload — so it degrades safely, but the Peers section AND every local ask card go dark together). This is the FIRST place in the codebase a raw git branch name reaches the wire at all (local ask-detail sessions never expose one). **Not fixed** — deliberately, since exempting branch/host names from the denylist would create a blind spot the check exists precisely to catch (a mechanism name COULD legitimately leak via a maliciously/accidentally named branch). **Possible fix directions:** (a) scope the denylist scan to exclude specific KEYS known to carry git-native strings (`branch`, `state_label`, `provenance_label`) the same way `HREF_KEYS`/`path` already gets a narrow, named exemption; or (b) degrade PER-PEER-ENTRY instead of whole-payload on a hit (drop just that one peer row with an honest "peer name flagged" note, not a global 500). Fold-in: next payload-schema.js touch, or when a real branch name actually trips this in production.

- **HARNESS-GAP-64 — `install-limit-resume-task.ps1` (Windows scheduled-task installer for the limit-resume watchdog) is written but UNTESTED — no Windows box available this session** (added 2026-07-30 from the limit-resume auto-arm build, `docs/decisions/068-macos-limit-resume-turn-scoped-auto-arm.md`; label: `harness-gap`, `priority:medium`). The script mirrors `install-estate-janitor-task.ps1`'s established pattern (hidden-window `.vbs` wrapper, idempotent `Register-ScheduledTask`/`Set-ScheduledTask`, `-WhatIf` dry-run, `-Uninstall`, never auto-registered from an agent session) line-for-line, but has not been run, registered, or exercised against a real Windows Task Scheduler. **Fix:** run it on a real Windows box, verify `Get-ScheduledTask -TaskName NL-LimitResume`, `Start-ScheduledTask` a one-shot tick, and confirm `~/.claude/state/limit-resume/log.txt` grows (or stays untouched if unarmed) exactly like the macOS LaunchAgent path already demonstrated.

- **HARNESS-GAP-65 — `scripts/needs-you.sh` is tracked in git as mode `100644` (non-executable), same defect class as the 2026-07-14 incident's I3 and decision 065's `ensure-cockpit.sh` prerequisite bug** (added 2026-07-30, noticed in passing while building the limit-resume watchdog and running `harness-doctor.sh --quick`; label: `harness-gap`, `priority:low`; pre-existing, unrelated to that build — confirmed via `git ls-files -s adapters/claude-code/scripts/needs-you.sh` showing `100644` at HEAD before any edit this session). **Fix:** `chmod +x adapters/claude-code/scripts/needs-you.sh && git add --chmod=+x adapters/claude-code/scripts/needs-you.sh` in whichever session next touches that file, or a dedicated one-line fix.

- **HARNESS-GAP-66 — the live `~/.claude/settings.json` mirror carries a duplicated/stale `SessionStart` `compact` matcher entry, pushing its live chain to 9 (budget-chains RED, budget <= 8) while the committed template stays at 8** (added 2026-07-30, noticed in passing while building the limit-resume watchdog; label: `harness-gap`, `priority:medium`; pre-existing, unrelated to that build — confirmed the committed template's `SessionStart` count is 8 both before and after this session's edits, and this session never touched the live mirror's `SessionStart` array). PROVEN: `python3 -c "import json; ..."` against `/Users/misha/.claude/settings.json` shows 3 `SessionStart` matchers (an OLDER `compact` entry whose text starts "STOP — Context was just compacted... 1. Read SCRAT...", a blank matcher, and a NEWER `compact` entry matching the current template's "0. READ THE HANDOFF SNAPSHOT..." wording) — `session-start-auto-install.sh`'s sync apparently merges/appends rather than fully replacing the `compact` matcher when its content changes, so an old version lingers alongside the new one. **Fix:** either make the sync fully replace (not merge) matcher-scoped hook arrays whose content changed, or add a one-time dedup pass; verify via `bash adapters/claude-code/hooks/harness-doctor.sh --quick` showing `budget-chains` GREEN for the live settings afterward.

## Open work — telemetry-gated (don't pick up yet)

- **HARNESS-GAP-11** — reviewer-accountability tracker. Gated on telemetry (2026-08 target).
- **Phase 1d-G calibration-mimicry** — same telemetry gate.



Strategy context and reasoning for many entries below lives in [`docs/claude-code-quality-strategy.md`](./claude-code-quality-strategy.md).

## Recently implemented (2026-05-04)

These items shipped in Phase 1d-E-1 (`docs/plans/phase-1d-e-1-p1-drift-fixes.md`):

- **HARNESS-GAP-09** — `plan-reviewer.sh` Check 1 + Check 5 false-positives narrowed via section-awareness (Check 1 only flags sweep language under `## Tasks` headings) + Tier A/B context-awareness (Check 5 runtime-keyword regex requires adjacency to database-context tokens). 4 new self-test scenarios added (commit b3951ba); 26-scenario self-test suite PASS.
- **HARNESS-DRIFT-01** — Six Gen-6 hooks confirmed wired in both template and live. `automation-mode-gate.sh` was the residual missing wiring; added to live (commit b973cf5). Other settings template-vs-live divergence remains in HARNESS-GAP-14's scope.
- **HARNESS-DRIFT-02** — SessionStart + push-time account-switching hooks replaced with config-driven `read-local-config.sh match-dir` calls (commits f2d812a template + 430365c evidence + live mirror). Decision 021 records the rationale: literal-substring approach rejected per its brittleness (identity leakage, single-org assumption, code-edit-to-add-account, false-positive fall-through).

These items shipped in Phase 1d-E-2 (`docs/plans/archive/phase-1d-e-2-audit-cleanup.md`):

- **Sub-gap A of the Build Doctrine integration audit batch** — Stop-hook orthogonality audit shipped (commit fd9f663). All 5 hooks (narrate-and-wait-gate, transcript-lie-detector, goal-coverage-on-stop, imperative-evidence-linker, deferral-counter) confirmed orthogonal; 2 pairs flagged CLARIFY BOUNDARY for documentation follow-up. Audit lives at `docs/reviews/2026-05-04-stop-hook-orthogonality.md`.
- **Sub-gap B of the audit batch** — `pipeline-agents.md` deleted from global rules (commit d8b30f3). Wholly project-specific; orchestrator pattern superseded the role framing. See Decision 022 for the alternatives considered and the rationale for deletion vs. relocation/generalization.
- **Sub-gap C of the audit batch** — `claim-reviewer` post-Gen6 reassessment shipped (commit d8b30f3). Verdict: KEEP as-is. Gen 6 hooks don't fully supersede; `claim-reviewer` remains the residual mitigation for verbal vaporware until Anthropic ships a PostMessage hook event. Reassess if/when that arrives. Audit lives at `docs/reviews/2026-05-04-claim-reviewer-reassessment.md`.
- **Sub-gap F of the audit batch** — Rules-vs-hooks audit shipped (commit d8b30f3). 24 rules audited; recommendations: 1 convert-to-stub, 4 split-into-stub-plus-extension, 19 keep verbose. Restructuring is OUT-OF-SCOPE for this plan; tracked via the audit document. Audit lives at `docs/reviews/2026-05-04-rules-vs-hooks-audit.md`.
- **Sub-gap H of the audit batch** — `docs/reviews/` gitignore convention documented (commit 7abe23e). Existing `.gitignore` was already correctly designed via date-prefix allowlist (`2026-*` → tracked). Documented the convention in `harness-hygiene.md` and added a sentinel comment in `.gitignore` itself.

These items shipped in Phase 1d-F (`docs/plans/archive/phase-1d-f-definition-on-first-use.md`):

- **HARNESS-GAP-10 sub-gap G** — Definition-on-first-use enforcement shipped (commits 7f24907 + this commit). Pre-commit hook scans *.md under build-doctrine/ for first-use acronyms; blocks if undefined in glossary or in-context. See Decision 023.

These items shipped in Phase 1d-E-4 (`docs/plans/archive/phase-1d-e-4-gap-15-cleanup.md`):

- **Audit gap sub-item A — scanner self-test repair.** `harness-hygiene-scan.sh --self-test` previously asserted an exemption for `docs/plans/foo.md` that had been deliberately removed. Self-test updated to assert the opposite (exit 1 on plan files); two new assertions added for the allow-list behavior. Commit f112226.
- **Audit gap sub-item B — scanner exemption logic tightened.** Directory-level exemption for `docs/decisions/`, `docs/reviews/`, `docs/sessions/` now applies ONLY to non-allow-listed paths within those directories. Allow-listed files (`NNN-*.md`, `YYYY-MM-DD-*.md`) ARE scanned. Full-tree scan after the fix surfaces 15 codename hits in committed decision/review files — these are the pre-existing leakage tracked separately as audit gap sub-item C. Commit f112226.
- **Audit gap sub-item D — automation-mode JSON schema authored.** `adapters/claude-code/schemas/automation-mode.schema.json` was claimed in `public-release-hardening.md` Task 6.1 but never authored at v1.0 publication. Schema now live with `{version, mode, deploy_matchers}`, version: 1 sentinel matching the existing four schemas. Commit 22c0e65.
- **Audit gap sub-item E — `public-release-hardening.md` properly closed.** Plan flipped to COMPLETED with honest annotations on the four previously-unchecked tasks: Task 1.2 scoped down per Option A; Task 4.2 shipped via HARNESS-DRIFT-02; Task 5.3 deferred with rationale; Task 6.1 shipped in commit 22c0e65. Auto-archived. Plan file is gitignored (would leak codenames if committed).
- **Audit gap sub-item F — `harness-quick-wins-2026-04-22.md` properly closed.** Plan flipped to COMPLETED. Phase A Task 1 (set `effortLevel: "xhigh"` in live `~/.claude/settings.json`) deferred with rationale: per-project `effort-policy-warn.sh` covers most of the value; global default flip is a personal-cost change best done interactively. 17 of 18 tasks remain shipped. Auto-archived. Commit ff5717d.

**Audit gap sub-item C — codename scrub before next master merge.** Still deferred per the right-sized P3 remediation plan. The scanner now reports the leakage (15 hits across 5 decision/review files), so the cleanup work has a verifier when it lands.

These items shipped in Phase 1d-E-3 (`docs/plans/archive/phase-1d-e-3-gap-14-reconciliation.md`):

- **HARNESS-GAP-14** — Template-vs-live `settings.json` reconciliation shipped (commits 84a0c61 audit + 9d3c2f0 reconciliation + this commit). Six per-hook proposals authored with originating-commit + plan + architecture-doc citations; all REVERSIBLE; auto-applied per discovery-protocol decide-and-apply. Five hooks added to template (`outcome-evidence-gate`, `systems-design-gate`, `no-test-skip-gate`, force-push/`--no-verify` blocker, `check-harness-sync` composition into pre-commit-gate); one hook upgraded in live (`public-repo` blocker to elaborate `read-local-config.sh public-blocked` form). Tool-call-budget matcher tightened to `Edit|Write|Bash` to match documented form. Post-reconciliation: `settings-divergence-detector.sh` PreToolUse counts equal between template and live (template=23, live=23). Out-of-scope SessionStart + UserPromptSubmit divergences (4-6 items) flagged in audit doc as follow-up; new backlog item to track. See Decision 024. Audit lives at `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md`.

These items shipped in Phase 1d-G (`docs/plans/phase-1d-g-final-cleanup.md`):

- **HARNESS-GAP-14 sub-item C — codename scrub before next master merge.** 15 hits across 5 committed decision/review files sanitized to generic placeholders (e.g., `<personal-account>`, `<work-org-codename>`, `<product-codename-X>`). Audit-trail readability preserved; substantive content unchanged. Full-tree scanner reports zero matches after scrub. DECISIONS.md gained a footnote acknowledging the in-place scrub of records 001, 002, 013 (no status or substance changes). Commit 6881712.
- **HARNESS-GAP-14-followups** — Four out-of-scope SessionStart/UserPromptSubmit divergences reconciled. Template was canonical for all four; live `~/.claude/settings.json` was updated to match: (1) compact-recovery hook stripped of hardcoded per-project subdirectory paths, (2) automation-mode initializer SessionStart block added, (3) legacy `claude-config` harness-sync hook removed (referenced pre-rename path), (4) UserPromptSubmit title-bar upgraded from basename-only to automation-mode-aware form. Verification: `jq -S '.hooks'` of live and template byte-identical; remaining file-level divergence is confined to the per-machine `permissions` array (intentional). Commit b27ab7e.
- **Rules-vs-hooks restructuring (observed-errors-first.md convert)** — Per Phase 1d-E-2 audit's recommendation, `observed-errors-first.md` was ~80% hook-enforced; converted to stub mirroring `vaporware-prevention.md`'s pattern (short opening + classification + enforcement-map table + cross-references). 25 lines (was 74). Synced to `~/.claude/rules/` (gitignored mirror). Commit ffff6e6.

Older closed items live in plan completion reports under `docs/plans/archive/`.

## HARNESS-GAP-08 — ABSORBED 2026-05-05 into `docs/plans/harness-gap-08-spawn-task-report-back.md`

Per backlog-plan-atomicity rule, the full entry is removed from open sections at the same commit as plan creation. Audit trail of the original entry preserved in git history at the commit prior to plan creation.

---

## HARNESS-GAP-10 — Seven gaps surfaced during Build Doctrine integration analysis (added 2026-05-03)

**Source.** Build Doctrine + Neural Lace deep comparative review (plan `~/.claude/plans/build-doctrine-cheerful-hearth.md`, completed 2026-05-03). Full evidence in `docs/reviews/2026-05-03-build-doctrine-integration-gaps.md` (gitignored — content is local-only; this entry is the public pointer). Seven sub-gaps named below; each is a candidate for Phase 1d-E (harness cleanup) per the unified methodology recommendation at `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md`.

**Sub-gap A — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (Stop-hook overlap analysis).

**Sub-gap B — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (`pipeline-agents.md` relocation/restructure).

**Sub-gap C — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (`claim-reviewer` post-Gen6 reassessment).

**Sub-gap D — PARTIALLY ABSORBED 2026-05-04 into `docs/plans/phase-1d-c-3-findings-ledger.md`.** C9 ships the findings-ledger substrate (`docs/findings.md` + schema gate + bug-persistence extension) that telemetry will eventually populate. The MANUAL-WRITE path is operational starting Phase 1d-C-3 — agents/gates write findings explicitly. The AUTOMATED-EXTRACTION path (LLM-assisted finding extraction from session transcripts) remains gated on telemetry's 2026-08 target. C13 (promotion/demotion) and Phase 1d-G (calibration-mimicry, deferred) can both proceed against the manual ledger; if telemetry slips, only the automation slips.

**Sub-gap E — ABSORBED 2026-05-04 into `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md`.** C16 behavioral-contracts validator implementation includes the concrete-invariants requirement (idempotency / performance budget / retry semantics / failure modes each ≥ 30 non-ws chars + no placeholder-only content). Vacuous-filler rejection is partial in 1d-C-2 (mechanical substance check); deeper semantic validation (e.g., "idempotency must reference a specific input→output mapping") deferred to a future plan if substance check proves insufficient.

**Sub-gap F — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (Rules-superseded-by-hooks audit).

**Sub-gap G — ABSORBED 2026-05-04 into `docs/plans/phase-1d-f-definition-on-first-use.md`** (Definition-on-first-use enforcement).

**Sub-gap H — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (`docs/reviews/` gitignore refinement).

**Cross-references.**
- Full review (gitignored, local-only): `docs/reviews/2026-05-03-build-doctrine-integration-gaps.md`
- Originating analysis: `~/claude-projects/Build Doctrine/outputs/analysis/03-comparative-analysis.md`
- Methodology recommendation: `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md`
- Recovery point for the integration: tag `pre-build-doctrine-integration` at NL master HEAD, branch `build-doctrine-integration` for Phase 1d work.

---

## HARNESS-GAP-11 — Reviewer accountability is one-way (added 2026-05-03)

**Source.** Surfaced during agent-incentive-map work (`docs/agent-incentive-map.md`, plan `docs/plans/agent-incentive-map.md`). Identified as a structural weakness in NL's adversarial-pairing architecture: when a reviewer agent (code-reviewer, task-verifier, end-user-advocate, harness-reviewer, systems-designer, ux-designer, claim-reviewer, plan-evidence-reviewer) PASSes work that subsequently fails at runtime acceptance OR fails in the next session OR fails in production, no signal flows back to the agent (or to a meta-tracker) for calibration.

**Why this is a gap.** Each reviewer's incentive to be careful is purely intrinsic — there is no consequence to PASSing too easily. Over time this creates calibration drift: reviewers pass borderline work because no penalty arrives when borderline work later fails. The user observed this pattern explicitly: "I don't trust the builder agents because they seem the most willing to find workarounds in order to call their work done." The same dynamic applies to reviewers — they have a structural incentive to take builders at their word because doing so is faster and friction-free.

This is the reviewer-side analogue of the documented `claim-reviewer` self-invocation gap in `~/.claude/rules/vaporware-prevention.md` ("the single unclosed gap from Generation 4"). Both are unaccountability gaps; both reduce the harness's actual quality below its nominal quality.

**Proposed mechanism.** Reviewer-calibration tracker — a new mechanism that:

1. Records every reviewer PASS verdict to `.claude/state/reviewer-passes/<reviewer-name>-<task-id>-<timestamp>.json` with: reviewer agent name, task ID, plan path, verdict, claimed-substance summary, file:line citations made.
2. When `enforcement-gap-analyzer` fires on a runtime acceptance FAIL OR `bug-persistence-gate` fires on a session-end with bug observations OR a future production-failure signal lands, it cross-references the reviewer-passes log to identify which reviewer last said PASS on the now-failed work. Surfaces the (reviewer, failed-work) pair to a per-reviewer calibration log at `.claude/state/reviewer-calibration-<reviewer-name>.md`.
3. Periodic audit: `/harness-review` weekly self-audit (a new check) reads each reviewer's calibration log and surfaces patterns: which reviewer's PASS verdicts most often precede later failures? That reviewer's prompt or rubric needs sharpening.

**Why this is a meaty mechanism (not first-pass).** Three implementation gates:

1. The mechanism depends on `enforcement-gap-analyzer` being able to attribute the failure to specific prior reviewer verdicts. That attribution requires Phase 1d-D telemetry (see HARNESS-GAP-10 sub-gap D — telemetry not yet shipped, blocks dependent mechanisms).
2. The mechanism depends on `findings-ledger schema` (C9) shipping so that "later failure" has a structured comparable form to the PASS verdict.
3. The mechanism's value compounds with TIME — a single PASS-then-FAIL pair is noise; a pattern of N PASS-then-FAIL pairs is signal. So the mechanism needs to ship and run for weeks before the audit produces actionable findings.

**Effort estimate.** L (~12-20 hours). One JSON-write helper for reviewer-pass logging, extension to `enforcement-gap-analyzer` for cross-reference, calibration-log format design, `/harness-review` audit extension, self-test scenarios.

**Why P2 (not P1).** Calibration drift is a slow-moving structural risk; it doesn't cause individual session failures. The first-pass C-mechanisms (C10 scope-enforcement, C22 quantitative-claims, C7-DAG-waiver — already shipped) catch immediate failure modes. C1/C2/C9/C15/C16 catch upstream failure modes. The reviewer-calibration mechanism catches drift across many sessions, which only matters once the harness is running stably enough to accumulate the pattern data. Sequence after Phase 1d-C-4 (C15 ships).

**Originating context.** The user posed (2026-05-03): "Show me the incentive and I'll show you the outcome — applied to AI agents." The agent-incentive-map document catalogued each agent's stray-from patterns; this gap is the most consequential unaddressed weakness across the catalogue.

---

## HARNESS-GAP-13 — ABSORBED 2026-05-05 into `docs/plans/harness-gap-13-hygiene-scan-expansion.md`

Per backlog-plan-atomicity rule, the full entry is removed from open sections at the same commit as plan creation. Audit trail of the original entry preserved in git history at the commit prior to plan creation.

---

## HARNESS-GAP-16 — ABSORBED 2026-05-05 into `docs/plans/harness-gap-16-closure-validation.md`

Per backlog-plan-atomicity rule, the full entry is removed from open sections at the same commit as plan creation. Audit trail of the original entry preserved in git history at the commit prior to plan creation (`e9985be`).

## HARNESS-GAP-16 — Plan-closure validation gate + `/close-plan` skill (historical entry — added 2026-05-05, absorbed into plan same day)

**Source.** Surfaced 2026-05-05 from the pre-submission-audit-mechanical-enforcement plan stranding incident. The plan was Status: ACTIVE since 2026-05-03 with all 5 task checkboxes empty despite all 5 tasks' code work being shipped on master. Recovery took ~2 hours of task-verifier dispatches + commit + closure. Root cause per user: bookkeeping discipline was not followed at session end; existing pre-stop-verifier did not catch it.

**Why this is a gap.** The harness has multiple Pattern-level rules requiring closure bookkeeping (verifier mandate, "update status documents when work completes", planning.md's plan-completion checklist) but no Mechanism that REFUSES the irreversible Status: COMPLETED transition until closure is mechanically complete. Sessions can flip Status without checking all bases, and once flipped + auto-archived, the audit trail is in a final state regardless of whether bookkeeping was done.

**Proposed mechanism — two layers:**

1. **Layer 1 (~2 hr): Extend `plan-lifecycle.sh` with closure-validation gate.** When an Edit changes Status from ACTIVE to COMPLETED, run mechanical checks BEFORE the auto-archive runs:
   - All task checkboxes are `[x]` in `## Tasks`
   - For each task ID, an evidence block exists in `## Evidence Log` with `Verdict: PASS`
   - `## Completion Report` section is present with non-empty Implementation Summary, Design Decisions, Known Issues sub-sections
   - For each `Backlog items absorbed:` entry in plan header, the backlog has been reconciled (item not in open sections)
   - SCRATCHPAD.md mtime within last hour AND mentions plan slug
   
   If any check fails, refuse the Status flip with specific error listing unmet items. Pre-flight gate, not backstop — refuses forward progress until closure work is real.

2. **Layer 2 (~1.5 hr): `/close-plan <slug>` skill.** Walks the orchestrator through closure mechanically:
   - Validates which Layer 1 checks currently pass; surfaces gaps with specific actions ("invoke task-verifier on Task 3", "update SCRATCHPAD")
   - Writes the completion report from `~/.claude/templates/completion-report.md`
   - Updates SCRATCHPAD + backlog
   - Flips Status (which triggers Layer 1 + auto-archive)
   - Commits + offers to push
   
   Makes the right path easier than the wrong path.

3. **Layer 3 (already landed 2026-05-05):** `feedback_complete_plan_bookkeeping_in_session.md` memory in `~/.claude/projects/.../memory/`. Behavioral reinforcement only.

**Why pre-flight gate (Layer 1) is different from a backstop.** This isn't a mechanism catching mistakes after the fact — it's a deterministic pre-condition gate. It runs BEFORE the irreversible action (Status flip + auto-archive). It refuses forward progress until closure work is satisfied. Compare: `pre-commit-tdd-gate.sh` is a pre-flight gate (refuses bad commits), not a backstop. Same shape.

**What it doesn't catch.** Terminal-killed sessions where Stop hook never fires. For those, `plan-status-archival-sweep.sh` already catches terminal-status plans at next session start. Could also extend that sweep to flag "ACTIVE plans whose tasks are all `[x]` but Status hasn't flipped" — half-closed plans visible at next session start (~30 min add).

**Effort estimate.** ~4-5 hr for Layers 1+2. Optional half-closed-detection extension ~30 min.

**Why scheduled next-after GAP-13** (per user 2026-05-05 sequencing decision): GAP-08 + GAP-13 ship user-facing improvements (orchestrator coordination + scanner expansion). GAP-16 is structural protection against the failure mode that just consumed effort to recover. Per user: "continue with GAP-08 + GAP-13 as planned per Option B, schedule this as next-after."

**Originating context.** Stranded plan recovery 2026-05-05 (commits `588b6db` + `4e8f658` on `verify/pre-submission-audit-reconcile` branch). User's framing: "the root cause of the problem is that you're not doing your due diligence and properly updating all the documentation when you complete a plan. That's what needs to be fixed." Discipline + memory landed (Layer 3); deterministic mechanism (Layers 1+2) deferred to this entry.

**Class.** `plan-closure-not-mechanically-gated` — irreversible terminal-status transition allowed without verified closure work.

---

## HARNESS-GAP-12 — Neural-lace dual-remote sync requires manual gh-auth dance (added 2026-05-03; STATUS: IMPLEMENTED 2026-05-04)

**Resolution.** Closed 2026-05-04 via SSH multi-push configuration on origin remote. See `docs/discoveries/2026-05-04-multi-push-ssh-config-implemented.md` for the full implementation log. `git push origin <branch>` now pushes to BOTH GitHub accounts atomically via per-Host SSH keys; auth-switch hook is irrelevant for neural-lace pushes.



**Source.** Surfaced 2026-05-03 during autonomous-delivery work. The harness's `git push` PreToolUse hook in `settings.json.template` calls `read-local-config.sh match-dir "$PWD"` and switches the active gh account based on directory pattern matching. For neural-lace specifically (dual-hosted: `origin = <personal-account>/neural-lace`, `pt = <work-org>/neural-lace`), the pattern matching switches to the wrong account on push, producing 403 errors. This recurred 2+ times in the same session.

**Why this is a gap.** Neural Lace is dual-hosted by design — pushes should reach BOTH GitHub accounts so the harness stays in sync across personal and work-org. The current setup has TWO distinct problems:

1. **Auth-switch fires wrong for neural-lace.** The local config's directory→account mapping doesn't have a tiebreaker for the dual-hosted case; the matcher picks one account, but if the push targets the other account's URL, it 403s.
2. **No automated dual-sync.** Even when one push succeeds, the OTHER remote isn't updated. The maintainer must remember to manually push to both, or accept that one remote drifts.

User stated requirement (2026-05-03): "Neural Lace needs to always be kept up to date in both GH accounts. They need to stay in sync. What's the best solution that automates this and keeps us from continuing to run into this issue?"

**Proposed mechanism.** Multi-push remote configuration plus per-host credential differentiation:

1. Configure `origin` as a multi-push remote: `git remote set-url --add --push origin <pt-url>` so a single `git push origin` sends to BOTH URLs.
2. Use SSH for one URL (typically the work-org), HTTPS for the other. SSH key auth bypasses the gh-active-account dependency entirely; HTTPS auth uses gh credentials for whichever active account.
3. The auth-switch hook becomes irrelevant for neural-lace pushes (both URLs auth independently).

Alternative simpler approach: explicit `neural-lace/` → `<personal-account>` mapping in `~/.claude/local/accounts.config.json` to fix the auth-switch. Doesn't solve dual-sync; manual `git push <work-org-remote>` still needed.

**Why this matters now.** Three commits this session hit the auth-switch failure, requiring manual `gh auth switch --user <personal-account>` + retry. This is recurring friction that should be fixed structurally rather than worked around.

**Effort estimate.** S (~30-60 minutes for multi-push + SSH config). Or XS (~5 minutes) for the local-config-only patch.

**Why P2.** Friction is meaningful but not a correctness threat — pushes still happen, just with extra steps. Schedule for Phase 1d-E (harness cleanup) alongside HARNESS-GAP-10 sub-gaps.

**Originating context.** Recurred during D4-discussion of the D1-D5 educational re-do (2026-05-03). The user pushed back on the recurrence: "I thought we set things up so that you're always aware of which account to use for each repo." The setup was correct for single-hosted projects; neural-lace's dual-hosting wasn't accounted for.

---

## HARNESS-GAP-14 — IMPLEMENTED 2026-05-04 via Phase 1d-E-3 (`docs/plans/archive/phase-1d-e-3-gap-14-reconciliation.md`)

See "Recently implemented" section above for commit SHAs + Decision 024. Follow-up entry below covers out-of-scope SessionStart / UserPromptSubmit divergences.

## HARNESS-GAP-14-followups — IMPLEMENTED 2026-05-04 via Phase 1d-G (`docs/plans/phase-1d-g-final-cleanup.md`)

See "Recently implemented" section above for commit SHA (b27ab7e). All four out-of-scope SessionStart/UserPromptSubmit divergences reconciled. Audit doc updated with the Phase 1d-G addendum at `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md`.

(Historical entry preserved below.)

## HARNESS-GAP-14-followups — Out-of-scope settings divergences from GAP-14 audit (added 2026-05-04)

**Source.** Audit `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md` "Out-of-scope divergences" section. Phase 1d-E-3 reconciled the named PreToolUse hooks; the divergence-detector still surfaces remaining items in SessionStart and UserPromptSubmit hook chains.

**The remaining divergences:**
1. SessionStart compact-recovery hook — live has hardcoded per-project subdirectory paths in its backlog/plan-glob lists; template canonical (per-project paths shouldn't live in the global hook).
2. SessionStart automation-mode initializer — present in template, NOT in live; template canonical (live missed update when automation-mode shipped).
3. SessionStart legacy `claude-config` harness-sync warn hook — present in template referencing `~/claude-projects/claude-config` (predates rename to `neural-lace`). Live correctly omits; template needs path correction or removal.
4. UserPromptSubmit title-bar hook — template version reads `automation-mode` from local config and includes it in the title; live is older form (just basename). Template canonical.

**Effort estimate.** S (~30-60 min when taken up). Apply the verdicts; verify divergence-detector reports clean output.

**Why P3.** Real divergence but the in-scope reconciliation closed the higher-impact PreToolUse drift. Each remaining item is a single-line fix with an obvious canonical side.

**Originating context.** Surfaced during Phase 1d-E-3 audit as out-of-scope drift not covered by the plan's named four hooks.

---

## HARNESS-GAP-37 — automation-mode-gate.sh blind to project config from worktrees branched pre-config (added 2026-05-17; STATUS: IMPLEMENTED 2026-05-17)

P1 friction. `automation-mode-gate.sh` resolved the project automation mode only from `$PWD/.claude/automation-mode.json`. A worktree whose branch predates the project's `full-auto` config commit has no such file → silent fallback to user-global `review-before-deploy` → deploy-class commands BLOCKED in a project that IS `full-auto`. **IMPLEMENTED:** parent-checkout fallback via `git-common-dir` (mirrors ADR 028's `session-wrap.sh` SCRATCHPAD resolution). New self-test Scenario 5 (positive + negative-control); 5/5 PASS; mirror synced byte-identical. Finding: NL-FINDING-003. See also NL-FINDING-004 (sibling worktree-resolution fix).

## HARNESS-GAP-38 — session-wrap.sh tracked-file freshness signals unclearable from a worktree (added 2026-05-17; STATUS: IMPLEMENTED 2026-05-17)

P1 friction. `session-wrap.sh` Signals 3/4/5 + `plans_touched` read `find_repo_root` = the PARENT checkout (correct for SCRATCHPAD per ADR 028, wrong for the TRACKED files docs/backlog.md / roadmap / discoveries that a worktree session edits in its own copy and ships via PR). The agent's correct action could not clear the signal — the check read the other checkout. **IMPLEMENTED:** new `find_worktree_root()`; `cmd_verify`/`cmd_refresh` take an optional `wt_repo` (defaults to `repo` → non-worktree + direct-call behavior byte-identical); tracked-file signals + `plans_touched` read the worktree root, SCRATCHPAD signals keep reading the parent. New S9a (proves the fix) + S9b (negative control — genuine staleness still STALEs, no masking). S1–S8 unchanged; 10/10 PASS; mirror synced. Finding: NL-FINDING-004. **Orthogonal to** the still-pending discovery `2026-05-17-session-wrap-signal3-transitive-false-fire.md` (separate root cause: the global 4h `--since` window mis-attributes which commits count — awaits Misha's decision; composes cleanly with this fix).

## HARNESS-GAP-41 — scope-enforcement-gate.sh trailing-slash matching didn't handle gitlink-shaped paths (added 2026-05-24; STATUS: IMPLEMENTED 2026-05-24)

P1. `scope-enforcement-gate.sh` rejected cleanup commits that removed gitlinks-as-directory-declarations from the index. **Symptom:** a plan declaring `<name>/ — gitlink to be deleted from index` for each of 30 Dispatch sibling-worktree gitlinks, paired with `git rm --cached <name>` for each, was blocked because the gate saw the staged paths as out-of-scope. **Root cause:** `glob_match()` at line 978, when handed a trailing-slash pattern `foo/`, used `[[ "$path" == "$pat"* ]]` which requires the staged path to include the trailing slash. `git rm --cached <dir>` against a mode-160000 gitlink stages the deletion as a bare path (`foo`) with no trailing slash — git tree entries for gitlinks don't carry one. The bare path didn't match the pattern-with-slash and the gate refused the commit. **Fix:** extended `glob_match()` to treat trailing-slash patterns as matching BOTH (a) any path under that prefix (existing behavior: `foo/` matches `foo/bar/baz`) AND (b) the bare path with no slash (NEW: `foo/` matches `foo`). False-positive guards preserved: `foo/` still does NOT match `foobar` or `foo-extra`. Shipped on branch `fix/scope-enforcement-gate-trailing-slash-parser-2026-05-24`. **Detection:** new self-test scenarios 17-20 (`trailing-slash-matches-bare-path`, `trailing-slash-matches-nested-path`, `trailing-slash-does-not-match-substring-prefix`, `trailing-slash-does-not-match-hyphen-extended`) would have caught this at commit time. 20/20 self-tests PASS post-fix. **Originating context:** the cleanup itself — 30 Dispatch sibling-worktree gitlinks accidentally swept into the index by `close-plan`'s `git add -A` on 2026-05-22 (commit `fff2de3`); cleanup composed with a `.gitignore` glob (`/[a-z]*-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/`) to prevent recurrence; full cleanup landed in the same commit as the parser fix via `docs/plans/archive/repo-cleanup-dispatch-worktree-gitlinks-2026-05-22.md`. Lesson: when extending `glob_match()` semantics, every directory-declaration shape must have a self-test covering both the prefix AND bare-path cases.

## HARNESS-GAP-36 — chronic per-session acceptance waivers on stale unstarted ACTIVE plans (downstream-project instance) (added 2026-05-17; STATUS: dispositioned-act — dedicated build session spawned)

P1. Concrete instance of the plan-staleness class already tracked by **HARNESS-GAP-29/30/31**. A downstream pre-customer project's `prd-v1.1-and-audit-resolution` plan (filed 2026-05-14, 0/7 tasks, Evidence Log empty, Task-5 migration absent) sat `Status: ACTIVE` 3 days; ~5 unrelated 2026-05-17 sessions in that project each hand-wrote an acceptance waiver (its SCRATCHPAD: "11 stale Status: ACTIVE plans force per-session acceptance waivers"). Diagnosis: gate firing CORRECTLY (real unstarted non-exempt ACTIVE plan, no PASS artifact); waivers are the correct per-session behavior; the defect is the unstarted work, not the gate. **Disposition:** dedicated downstream build session spawned via `mcp__ccd_session__spawn_task` to drive all 7 tasks to PASS + `Status: COMPLETED` (stops the waiver tax at root). Finding: NL-FINDING-005. **Systemic fix remains GAP-29/30/31** — this entry is the trigger instance, not a new class. The broader observation (≥11 stale ACTIVE plans in that project) is the GAP-29/30/31 aggregation gap manifesting concretely.

## HARNESS-GAP-17 — User-facing narrative docs stale; docs-freshness-gate has narrative-doc blind spot (added 2026-05-05; renumbered from GAP-16 to GAP-17 on 2026-05-05 — duplicate-numbering conflict with closure-validation entry above)

**Status (2026-05-05):** Part A IMPLEMENTED in this session. All 5 narrative docs updated to reflect Gen 5/6 + Build Doctrine integration arc — README.md (Gen 5/6 + Build Doctrine highlights, Status table extended), `adapters/claude-code/CLAUDE.md` (5-mode framework + Gen 5/6 sections + Build Doctrine integration block + Counter-Incentive Discipline + Detailed Protocols expanded; live mirror synced), `docs/harness-strategy.md` (milestones for Gen 5/6 + Build Doctrine arc, security maturity table extended with anti-vaporware / narrative-integrity / spec-discipline / hygiene rows), `docs/best-practices.md` (six new pattern entries: Discovery Protocol, comprehension gate, plans as living artifacts, PRD validity + spec freeze, findings ledger, definition-on-first-use; References section expanded with all new rules + decision records), `docs/claude-code-quality-strategy.md` (Build Doctrine arc framing, generation arc up to Gen 6, mechanism stack tables extended for "Adversarial separation" / "Determinism via mechanism" with Gen 5/6 + Build Doctrine entries, Known Gaps section updated to reflect Gen 6 partial closure of verbal-vaporware gap and explicit GAP-16 plan-closure-discipline gap, References section lists decision records 011-024). Part B (gate extension) remains deferred per the original P2 estimate. Originating commit on this branch.

**Source.** Surfaced 2026-05-05 when user asked "Have we updated the documentation to reflect these updates?" Investigation revealed substantial drift between mechanism-tracking layer (current via docs-freshness-gate enforcement) and narrative/orientation layer (stale, no enforcement).

**Why this is a gap (two-part).**

**Part A — content drift.** After ~11 phases of Build Doctrine + NL integration work shipping new mechanisms (scope-gate redesign, discovery protocol, comprehension-gate, definition-on-first-use, multi-push, push-policy change, plus 12 new decision records 013-024), the user-facing narrative docs are stale by 1-2+ weeks:

- `README.md` (last touched 2026-04-29) — pre-dates entire integration arc
- `docs/harness-strategy.md` (last touched 2026-04-18) — pre-dates Build Doctrine entirely
- `docs/best-practices.md` (last touched 2026-04-27) — missing all new patterns (educational decision format, in-flight scope updates, no-waiver gate model, calibration mimicry framing, discovery protocol)
- `docs/claude-code-quality-strategy.md` (2026-04-24) — pre-Build Doctrine
- `adapters/claude-code/CLAUDE.md` (2026-04-24) — missing Counter-Incentive Discipline patterns, discovery protocol, educational-format requirement

**Part B — structural blind spot.** `docs-freshness-gate.sh` only fires on Add/Delete/Rename of hooks/rules/agents/skills. It catches structural surface-area changes but doesn't require updates to narrative docs that should propagate from those changes. The harness gained 11 mechanisms; the gate dutifully required `harness-architecture.md` preface annotations for each but didn't require the same propagation to `README.md` or `best-practices.md` because those aren't in its detection set. This is the documentation analogue of FM-023 (vaporware-spec-misunderstood-by-builder) — gates that look right on the surface but miss a class of drift.

**Proposed action — two parts.**

1. **Documentation sweep** (~3-5 hours, dedicated plan). Update the 5 stale narrative docs to reflect current mechanism state. README.md gets the highest priority since it's the public-facing first-impression artifact. Best-practices.md needs the most additions (new patterns and rationales). Strategy.md and quality-strategy.md need milestone updates. CLAUDE.md needs the Counter-Incentive Discipline + educational-format additions.

2. **Extend `docs-freshness-gate.sh` to require narrative-doc updates** when N or more hooks/rules/agents/skills change in a defined window OR when major decision records (Tier 2+) land. Mechanism: a periodic full-tree audit (could compose with `/harness-review` weekly skill) that diffs the harness-architecture.md preface chain against the README's claimed-features section and surfaces stale narrative.

**Effort estimate.**
- Part 1 (sweep): M (~3-5 hours). Pure docs work, no mechanism changes, low risk.
- Part 2 (gate extension): M-L (~6-10 hours). Heuristic detection design + integration with /harness-review.

**Why P1 for Part 1, P2 for Part 2.** Part 1 is content drift that affects every fresh user/session's first orientation; high reach, fixable with focused effort. Part 2 prevents recurrence but is structural mechanism work that should land after the initial sweep produces empirical data on what kinds of changes the gate should detect.

**Originating context.** User asked 2026-05-05: "These updates to NL are substantial. Have we updated the documentation to reflect these updates?" Quick verification confirmed the gap.

---

## Pre-existing harness drift surfaced 2026-04-27 (during agent-teams conflict analysis)

Items found while doing the Phase 1 ground-truth inventory for Agent Teams integration. Two items (P2-class) were absorbed into `docs/plans/agent-teams-integration.md` on plan creation; HARNESS-DRIFT-01 and HARNESS-DRIFT-02 were absorbed into `docs/plans/phase-1d-e-1-p1-drift-fixes.md` on 2026-05-04.

## Known gaps in current enforcement (from strategy doc, 2026-04-22)

These are residual risks in the Gen 4+ harness. Each is documented honestly rather than left hidden.

### P1 — Verbal vaporware in conversation is not mechanically blocked

Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped. When the agent makes a feature claim in conversation without citing file:line, no mechanism catches it. Current mitigation: user reflex to ask for citations. Closing requires either a PostMessage hook in Claude Code itself or an adversarial post-response review agent that fires on every Nth response.

### P1 — Tool-call-budget `--ack` attestation is bypassable

**(absorbed by docs/plans/nl-overhaul-program-2026-07.md — D.6 retirement)**

The `tool-call-budget.sh` hook looks for sentinel lines in `~/.claude/state/reviews/`. A builder agent could Write that file directly without actually invoking `plan-evidence-reviewer`. Friction is raised but not cryptographically closed. Closing requires either per-session HMAC signing or architectural support for observing Task tool invocations.

### P1 — Concurrent-session state collisions (plan-wipe incidents)

Multiple Claude Code sessions on the same machine share `~/.claude/` state and the git working tree. Uncommitted plan files have been lost to concurrent-session `git stash`/`clean` operations on multiple documented occasions (2026-04-19, 2026-04-20). A project-level plan addressing commit-on-creation is in flight, but cross-session state coordination (shared `~/.claude/` directory) is still unresolved.

### P2 — `plan-lifecycle.sh` archival staging misses content change

Surfaced 2026-04-23 (during plan #5's own self-archival, commit 93ef15d). When the Status field is edited, the hook stages a `git mv` to archive but does NOT stage the actual Status text change. Resulting commit captures the rename only; the content change sits unstaged in the working tree at the new path, requiring a manual follow-up `git add <new-path> && git commit`.

**Fix candidates:**
- (a) Hook also runs `git add <new-path>` after the `git mv` so the content change is staged together with the rename. Risk: if the new path doesn't exist yet (race condition with the rename being staged but not committed), `git add` may fail.
- (b) Hook emits a clear warning message reminding the user to `git add <new-path>` before committing. Pattern enforcement, not mechanism.
- (c) Hook moves the file via `mv` (filesystem rename) BEFORE the Edit tool's content change reaches disk, then user does `git add -A` which captures both as a single staged change. Requires hook re-architecture.

Workaround pattern (used 2026-04-23): commit twice — first commit captures the rename (zero-content change), second commit captures the Status text update. See plan #5's archival commits 93ef15d + 6f4c057.

### P1 — Concurrent ACTIVE plans need acceptance-exempt declaration before next session-end (2026-04-24)

After Phase D of `docs/plans/end-user-advocate-acceptance-loop.md` registered `product-acceptance-gate.sh` as Stop-hook position 4, two concurrent ACTIVE plans will block session end on the next session unless reconciled:

- `docs/plans/claude-remote-adoption.md`
- `docs/plans/class-aware-review-feedback-smoke-test-plan.md`

Both are harness-dev plans without a product-user surface. Per `rules/acceptance-scenarios.md`'s exemption guidance, each should declare `acceptance-exempt: true` with a substantive `acceptance-exempt-reason:` (>= 20 chars). The third concurrent plan, `end-user-advocate-acceptance-loop.md` itself, has already been declared exempt in Phase D (bootstrap meta-plan rationale).

**Fix path:** in the next session, edit each plan file's header to add the two fields. Example for `claude-remote-adoption.md`:
```
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan (Claude Code remote-mode adoption); no product-user surface to verify at runtime — the maintainer exercises the harness in subsequent sessions.
```

Until done, sessions ending while these plans are ACTIVE will hit a BLOCK with a clear remediation message from `product-acceptance-gate.sh`. Per-session waiver is also available as a fallback (`echo "..." > .claude/state/acceptance-waiver-<slug>-$(date +%s).txt`).

### P1 — `plan-phase-builder` sub-agent dispatched without Task tool — cannot invoke `task-verifier` (2026-04-23)

**Flagged for harness-reviewer 2026-04-27:** the agent-teams integration session re-encountered this gap (commits f993a83, ed42e8b, ff28441, 6cca4b8 — Phase 5 Tasks 1-4 of `docs/plans/agent-teams-integration.md`). The evidence-first fallback worked end-to-end across four builders, providing additional empirical confirmation that path (b) below is viable. Next `/harness-review` skill run should evaluate which fix to commit to.

When the orchestrator dispatches a `plan-phase-builder` sub-agent (the dispatch type used while building Phase A of `docs/plans/archive/robust-plan-file-lifecycle.md`), the sub-agent's tool surface does NOT include the Task tool — it is not in the top-level tool list and is also not surfaced via ToolSearch (`select:Task` returns no results). Consequence: the sub-agent cannot invoke `task-verifier` as instructed by both the orchestrator-pattern rule and the dispatch prompt. The builder must fall back to writing evidence blocks directly under the evidence-first protocol enforced by `plan-edit-validator.sh` + `runtime-verification-executor.sh` — which works (the harness was specifically designed to allow this path), but it conflicts with the rule's "only `task-verifier` flips checkboxes" framing. Two possible fixes: (a) ensure dispatched `plan-phase-builder` sub-agents inherit the Task tool so they can invoke `task-verifier`; (b) update `~/.claude/rules/orchestrator-pattern.md` and the dispatch-prompt boilerplate to explicitly authorize the evidence-first fallback when Task is unavailable, with a written rationale. Either way, the current mismatch between the rule and the runtime tool surface should be reconciled. Reference instances: original Phase A build (commits d2d1494 + 4cc9c2a on `feat/robust-plan-file-lifecycle`); agent-teams integration Phase 5 Tasks 1-4 (commits f993a83, ed42e8b, ff28441, 6cca4b8 on master, 2026-04-27).

## Improvements surfaced by a downstream plan-staleness sweep (2026-04-24)

Seven structural gaps that allowed ~22 ACTIVE plans to accumulate across two sibling project repos without any enforcement firing. Each entry is named HARNESS-GAP-NN for cross-reference. Surfaced during a Q&A session that hit the `product-acceptance-gate.sh` Stop hook in storm — the gate fired, the user asked "why are so many plans considered done without everything checked off?", and these are the answers.

### HARNESS-GAP-01 — `pre-stop-verifier.sh` doesn't block terminal-Status flips with unverified tasks

`pre-stop-verifier.sh` blocks "checked tasks without evidence blocks" AND "unchecked tasks AND `Status: ACTIVE`." It does NOT block "terminal Status (`COMPLETED` / `DEFERRED` / `ABANDONED` / `SUPERSEDED`) AND unchecked tasks AND no evidence block names them shipped." Consequence: the cleanup move (flip Status to clear the gate) silently legitimizes whatever checkbox state is in the file — the precise pattern that produced a downstream plan-staleness sweep. Proposed fix: add Check 4d to `pre-stop-verifier.sh` that requires every unchecked task in a terminal-Status plan to either (a) have an evidence block claiming it shipped, or (b) appear in an explicit "Tasks deferred to Phase 2 / out of scope" section in the closing note.

### HARNESS-GAP-02 — No git-log → plan-checkbox correlation

A commit that touches files in a task's `Files to Modify/Create` list could plausibly satisfy that task, but no hook reads the diff, finds the matching task, and surfaces "this commit may satisfy Task X.Y in plan Z — invoke task-verifier?" Sync is one-way: builder must remember. If the builder errors, exits, or work goes through any non-orchestrator path (manual fix, hotfix, kanban-engine direct commit), the link is never formed. Proposed fix: PostToolUse hook on Git commits that scans the commit's diff against `docs/plans/*.md` ACTIVE plans' file lists and emits a non-blocking surface message naming the candidate tasks. User or next session can act on it.

### HARNESS-GAP-03 — Auto-generated kanban plans bypass task-checkbox enforcement

Plans created by `kanban-engine.yml` from GitHub Issues have task lists that read "(The build agent will investigate, diagnose, and implement autonomously.)" — i.e., 0 checkboxes by design. The verification model assumes plans have task lists. Kanban plans don't, so `pre-stop-verifier`'s "unchecked tasks" check is vacuously satisfied — but there's also no positive signal that the work shipped. The kanban plan can sit at `Status: ACTIVE` indefinitely while the underlying GitHub Issue is closed. Proposed fix (two parts): (a) `Status: ISSUE-TRACKED` sentinel that exempts kanban plans from task-checkbox enforcement and treats issue-close as the verification, (b) periodic Routine that scans kanban plans whose source issue is CLOSED and auto-flips Status: COMPLETED.

### HARNESS-GAP-04 — Reactive audit, not preventive

a downstream plan-staleness sweep exists in the backlog because the `product-acceptance-gate.sh` Stop hook started failing loudly enough that someone noticed 22 stale plans. There's no scheduled "weekly plan-audit" Routine that surfaces stale plans before they accumulate. By the time you see drift, you have 22 plans to triage, the sweep takes hours instead of minutes, and the user's confidence in the gate erodes. Proposed fix: weekly `/schedule` Routine that lists every plan with `Status: ACTIVE` for >14 days where the most recent commit touching `docs/plans/<slug>` is >7 days old. Output goes to `docs/reviews/YYYY-MM-DD-plan-staleness-audit.md` so it's actionable at human scale.

### HARNESS-GAP-05 — Status-audit sub-agents conflate "code shipped" with "feature works"

When a research / status-audit sub-agent reports on a plan (e.g., "the roadmap is functionally complete"), the agent typically correlates checkbox state with git log — both static signals. It does NOT exercise the feature at runtime. The `end-user-advocate` exists for runtime verification but is not invoked by status-audit agents by default. Result: a plan can be reported "done" based on artifacts that exist on disk, without anyone ever confirming a real user can use the feature. Proposed fix: either (a) extend `task-verifier`'s verdict shape to distinguish `evidence: artifact-only` from `evidence: runtime-PASS` and require runtime evidence for any task whose `Done when:` criterion involves user-observable behavior, OR (b) add a rule that any agent reporting "this plan is done" must call out which checks were performed and which were skipped, in a structured `## Verification Coverage` block.

### HARNESS-GAP-06 — No first-class `Status: PENDING-REVIEW` for "code shipped, human QA pending"

The current terminal Status taxonomy (`COMPLETED`, `DEFERRED`, `ABANDONED`, `SUPERSEDED`) lacks an honest label for the very common state "the engineering work shipped but the user hasn't yet exercised it to confirm the build matches their expectation." Sessions are forced to choose: leave Status: ACTIVE (gates fire forever) or flip COMPLETED (loses the "I haven't actually tried this yet" signal). Workaround in the surfacing project: pair `Status: COMPLETED` with `MANUAL-QA-<plan-slug>` backlog items.

Proposed fix: real `Status: PENDING-REVIEW` sentinel honored by the harness — plan auto-archives like other terminal statuses, but session-end gate emits a non-blocking reminder listing pending-review plans the user should triage. The sub-status `PENDING-REVIEW` ages out into `COMPLETED` after explicit user sign-off (or `DEFERRED` if QA found regressions).

**User-supplied requirements (refined 2026-04-24):**

1. **MUST NOT block continued progress.** A plan in `PENDING-REVIEW` does NOT trigger acceptance gates, does NOT gate session end, does NOT gate dispatch of new builders, does NOT block other plans from being created or worked. The only signal is informational. Specifically: `product-acceptance-gate.sh` must treat `PENDING-REVIEW` as equivalent to `acceptance-exempt` for blocking purposes; `pre-stop-verifier.sh` must treat `PENDING-REVIEW` as a terminal status for completion-check purposes.

2. **Persistent roadmap-level + plan-level overview.** A dashboard (or session-start surface) that shows what's pending review at both levels:
   - **Plan level:** within a plan file, individual tasks could carry per-task review state (`- [x] Task 1 (PENDING-REVIEW)` vs `- [x] Task 1 (REVIEWED 2026-04-25 by user)`). Lets the user know which specific tasks within a plan they've actually verified.
   - **Roadmap level:** a Routine or skill that scans all plans (active + archived) and produces a dashboard at `docs/reviews/<date>-pending-review-dashboard.md` (or surfaces in SCRATCHPAD on session start). Lists every plan currently in `PENDING-REVIEW` with a one-line summary of what's awaiting verification and how long it's been waiting. Roadmap docs (like `an active project roadmap doc`) should be able to query this state inline.

3. **Sign-off discipline.** The transition `PENDING-REVIEW` → `COMPLETED` requires an explicit user-attributed reviewed-by/reviewed-on annotation in the plan or a companion review file. Prevents the agent from silently flipping it on the user's behalf.

4. **Roadmap-aware archival.** Plans that are owned by an active roadmap (e.g., `an active project roadmap doc`) should not auto-archive on `PENDING-REVIEW` — they stay reachable from the roadmap until the user signs them off and the roadmap itself updates the link. Otherwise the user loses the "where are we on the roadmap" overview that the roadmap doc is supposed to provide.

These requirements push HARNESS-GAP-06 from a small Status sentinel to a small subsystem (status semantics + dashboard generator + review annotations + roadmap-awareness). Scope it as a multi-phase plan when picking up. P1.

### HARNESS-GAP-07 — `plan-lifecycle.sh` doesn't recognize YAML frontmatter Status

Surfaced 2026-04-24 during a downstream plan-staleness sweep Phase 1 closures. The hook's awk pattern `/^Status:[[:space:]]*[A-Za-z][A-Za-z0-9_-]*/` matches only the standard `Status: ACTIVE` line at the top of a plan. It does NOT match YAML frontmatter format where the field is `status: ACTIVE` (lowercase) inside a `---` block. Reference instance: a kanban-engine-generated plan in a downstream project had to be manually `git mv`'d to archive because flipping its YAML frontmatter `status:` to `COMPLETED` did not trigger the hook. Two fix options: (a) extend the hook's awk pattern to also recognize YAML frontmatter `status:` lines (case-insensitive), OR (b) add a pre-commit hook (`plan-format-normalizer.sh`) that detects YAML frontmatter plans and either rewrites them to standard format or refuses the commit with a message pointing at the standard. Option (a) is non-invasive but legitimizes two formats; option (b) forces consistency. Light P2 — rare format outside the kanban-engine pipeline, but the inconsistency surprises operators when archives don't auto-fire.

### HARNESS-GAP-08 — No `Status: REFERENCE` for index/roadmap docs in `docs/plans/`

Surfaced 2026-04-24, recurring 2026-05-06. The Status taxonomy (`ACTIVE` / `COMPLETED` / `DEFERRED` / `ABANDONED` / `SUPERSEDED`) has no honest label for docs that live in `docs/plans/` but are NOT units of work — they're indexes, roadmaps, or reference material that point AT the actual plans. Reference instance: a downstream project has a roadmap doc at `docs/plans/<roadmap-name>.md` (0/0 task list) that tracks 6 workstream plans. With `Status: ACTIVE` it triggers `product-acceptance-gate.sh` (no PASS artifact ever exists) and pollutes the active-plan view at session start. With `Status: COMPLETED` it auto-archives away from active reach. The user explicitly wants such docs accessible AS reference, not closed. Three fix options: (a) `Status: REFERENCE` sentinel that exempts from acceptance gate + plan-staleness sweeps + auto-archival, while keeping the file at top-level `docs/plans/`; (b) introduce a `docs/roadmaps/` directory that's not gated; (c) accept the inconsistency and document as Pattern that operators avoid putting reference docs in `docs/plans/`. Option (a) is most expressive — orthogonal status field for "is this a unit of work?" — but adds complexity. Option (b) is cleaner architecturally; requires migrating existing roadmap docs. Light P2; mostly affects operators with concentrated multi-plan campaigns (audit campaigns, large refactors). The 14-plan PLAN-SWEEP-01 Phase 2 on a downstream project (2026-05-06) had to skip 1 ACTIVE plan that was a roadmap doc, surfacing the gap a second time.

## Improvements surfaced by 2026-04-22 strategy review

Prioritized order of leverage. Full reasoning in `docs/claude-code-quality-strategy.md` section "Additional Suggestions for Improvement."

### P0 — Harness-tests-itself: synthetic session runner

**(absorbed by docs/plans/nl-overhaul-program-2026-07.md — E.4)**

Build a tool that runs synthetic Claude Code sessions against known-bad scenarios and measures whether hooks catch them (unauthorized checkbox flip, mocked integration test, uncited feature claim, budget exhaustion without audit). Runs on demand or weekly via `/schedule`. Produces a report showing which enforcement mechanisms have regressed. This catches silent enforcement regressions — currently invisible.

### P2 — Claude Code doesn't dynamically load new agents OR hooks added mid-session

Surfaced 2026-04-23. Two confirmed instances of the same root cause:

- **Agents:** the `plan-phase-builder` agent file exists at both `~/.claude/agents/plan-phase-builder.md` and `adapters/claude-code/agents/plan-phase-builder.md`, but a session that started before the file was added returns "Agent type 'plan-phase-builder' not found" when invoked via the Task tool. Workaround: use `general-purpose` agent with orchestrator-pattern discipline inlined in the prompt.
- **Hooks:** the `plan-deletion-protection.sh` hook was registered via `jq` into `~/.claude/settings.json`'s PreToolUse Bash matcher mid-session. A subsequent `rm docs/plans/dpc-test.md` (which the hook should BLOCK per its self-test scenario 1) was NOT blocked — the file was deleted with exit code 0. The hook's `--self-test` passes 14/14 in a fresh subprocess invocation, proving the hook logic is correct. The session simply isn't aware of the new hook registration. Workaround: end and re-start the session (or rely on next-session activation, which is acceptable for non-urgent enforcement additions).

Mitigation candidates:
- (a) Document the limitation in `harness-maintenance.md` so future Claude sessions know to restart after adding new agents.
- (b) SessionStart hook that re-scans `~/.claude/agents/` and writes a "missing agents" warning if any expected agent isn't loaded — surface staleness without forcing a restart.
- (c) Investigate whether Claude Code has an agent-reload command; if so, document it.

Low priority because the workaround (general-purpose dispatch with inlined discipline) is functional and the issue resolves on next session start.

### P1 — Class-aware reviewer feedback Mod 2: pre-commit class-sweep attestation hook

Deferred from the original bundled "Class-aware reviewer feedback (narrow-fix bias mitigation)" entry on 2026-04-23. Mods 1 + 3 of that entry are absorbed by the `class-aware-review-feedback` plan. Mod 2 stays in the backlog pending evidence that Mods 1+3 alone don't fully close the narrow-fix-bias pattern.

**Pattern this would address:** adversarial reviewers identify named instances; LLM builders fix the named instances; sibling instances of the same defect class slip; next pass surfaces a sibling; loop. Surfaced across 5 `systems-designer` iterations on the `capture-codify-pr-template` plan (2026-04-23). Affects every adversarial-review loop in the harness.

**Proposal:** New PreToolUse hook `class-sweep-attestation.sh` (matching `git commit`) that detects fix-commits — message contains "amend" / "fix" / "address review" AND a prior reviewer FAIL exists in `~/.claude/state/reviews/`. Requires the commit message to include a `Class-sweep: <pattern> — N matches, M fixed` line. Blocks commit otherwise. Estimated effort: ~6 hrs (with self-test); existing `bug-persistence-gate.sh` is a good template.

**Trigger to revive:** if after `class-aware-review-feedback` ships, an adversarial-review loop still produces 3+ rounds of FAIL where each round surfaces a sibling instance of a defect class the prior round was supposed to address, that's the signal to ship Mod 2. Until then, the prose-layer interventions (Mod 1 + Mod 3) are believed sufficient.

### P1 — Verify class-aware reviewer feedback in next session (live agent invocation) (2026-04-23)

The `class-aware-review-feedback` plan completed Task A.10 with the smoke-test fixture at `docs/plans/class-aware-review-feedback-smoke-test-plan.md` and a sweep-query verification (9 matches against the seeded class), but could NOT live-invoke the modified `systems-designer` agent because (a) sub-agents dispatched as `plan-phase-builder` lack the Task tool (P1 above), and (b) agent definitions are loaded at session start, so in-session prompt edits don't activate until the next session (P2 below). Next-session work: invoke the modified `systems-designer` agent on the smoke-test fixture (or a fresh equivalent) and verify the agent output contains the six-field block structure (`Line(s):`, `Defect:`, `Class:`, `Sweep query:`, `Required fix:`, `Required generalization:`) for at least the seeded `generic-placeholder-section` defect class. Compare the agent's emitted sweep query against the expected sweep query in the evidence file's section C. If the agent does NOT reliably emit the six-field structure, that's the signal to either tighten the prompt language or escalate to Mod 2 (the pre-commit `class-sweep-attestation.sh` hook above). After verification, the throwaway smoke-test fixture file can be deleted.

### P1 — Prompt template library for meta-questions

Codify canonical meta-questions as slash commands or skills: `/why-did-this-bug-slip`, `/find-my-bugs`, `/make-this-plan-verbose`, `/harness-this-lesson`. Currently these patterns live in individual memory; codifying makes them reusable and consistent.

### P1 — Delegability classification on plan tasks

Every plan task declares: fully-delegable / review-at-phase / interactive. Shapes dispatch automatically — fully-delegable auto-dispatches to background sessions, review-at-phase produces PRs at phase boundaries, interactive stays in foreground. Replaces per-task manual routing decisions.

### P1 — Explicit interactive vs autonomous session mode

Session-start directive declaring interactive (human watching; more permissive) or autonomous (human not watching; stricter gates, auto-commit plans, harder enforcement). Same cadence shouldn't apply to both modes.

### P2 — Effort-level enforcement at project level

`.claude/minimum-effort.json` in project root declares minimum effort level. SessionStart hook warns if effort is below project minimum. Eliminates "forgot to set max" errors on quality-critical projects.

### P2 — Multi-model routing strategy

Codify model assignment per task type: Opus for planning/adversarial review/judgment; Sonnet for implementation; Haiku for mechanical operations. Partially done via individual agent frontmatter; could be more systematic via a central routing config.

### P2 — Scheduled retrospectives via `/schedule`

Weekly scheduled agent that reads the week's completed plans, decisions, and failure-mode entries; proposes harness improvements based on patterns; drafts `docs/retrospectives/YYYY-WW.md`. Turns ad-hoc "half my time on the harness" into systematic weekly attention.

### P2 — Session observability dashboard

Lightweight `claude-status` command aggregating active sessions (local + `--remote`), active plans, tool-call budget consumption, recent hook firings, uncommitted work at risk of wipe. Aggregates existing state files — no new infrastructure needed.

### P2 — Harness version contracts

Each project declares `harness-version: >=N` in its CLAUDE.md. Breaking harness changes bump the version. SessionStart warns if project version predates current harness. Prevents silent regressions as harness evolves beyond what older projects expected.

### P2 — Validate Decision 011 Approach A end-to-end via real `claude --remote` session (2026-04-23)

Plan #4 (`docs/plans/claude-remote-adoption.md`) Phase B set up Approach A on a reference downstream project (a small work-account demo repo on GitHub) — `.claude/` directory exists in that project's working tree with the harness committed-copy form per Decision 011, but the `git commit` and `git push` were deferred because the reference repo had no configured user identity and the builder did not have authority to set it.

Required user action:
1. From the reference project's directory: confirm the appropriate git identity is set (one-time per-machine), then `git add .claude/ && git commit -m "chore: adopt Neural Lace harness via project .claude/ (Decision 011 Approach A)" && git push`.
2. Launch `claude --remote "list every rule loaded for this session and confirm any one hook fires"` against the reference project's pushed branch.
3. Confirm: (a) cloud session enumerates the rules in `.claude/rules/` matching the local set, (b) at least one hook from `.claude/settings.json` fires during the session, (c) `task-verifier` agent is dispatchable from the cloud session.
4. If any of (a)/(b)/(c) fails, file the failure mode against Decision 011 — Approach A may need refinement (e.g., symlink fallback, settings.json adjustments for cloud).

This is the integration test referenced in Decision 011's Test Plan section, and the empirical validation deferred from Phase A.



### P1 — Mysterious `effortLevel` wipe during session (2026-04-22/23)

Observed: `~/.claude/settings.json` started the session with `effortLevel: "max"`. Partway through, a subsequent `jq -r '.effortLevel'` returned `null` (key removed or value nulled). No task in the executing plan intentionally touched this field. Neither the main session nor any dispatched builder agent reported editing it.

Plausible causes:
- A PreToolUse or PostToolUse hook silently normalizing settings.json (e.g., a JSON rewriter that drops unknown keys)
- A concurrent session on the same machine overwriting settings.json with an older version (the concurrent-session state collision pattern we already have logged)
- An `install.sh` re-run during the session restoring from a template that had the key but was processed incorrectly
- A tool call with a full-file Write to settings.json that didn't preserve the effortLevel field

Remediation needed:
- Audit every hook that reads/writes `~/.claude/settings.json` for normalization that could drop top-level keys
- Consider adding a SessionStart hook that snapshots `settings.json` to `~/.claude/state/settings-snapshot.json` and, on next SessionStart, diffs against the current file to surface silent mutations
- Document the root cause once identified, then add a test/guard

Until fixed: users should periodically check `jq -r '.effortLevel' ~/.claude/settings.json` is not `null`. The existing `effort-policy-warn.sh` hook catches this indirectly (will warn if env var is unset and settings is missing the key AND policy requires non-low).

### P1 — Harness-work plans have no tracked home

Per `harness-hygiene.md`, the harness repo adds `docs/plans/` to `.gitignore` (harness repos don't ship instance artifacts). But harness-dev work DOES produce plan files, and those plans have no naturally-tracked home:

- `neural-lace/docs/plans/` — gitignored; plans there survive locally but aren't protected from `git clean`
- `~/.claude/plans/` — outside any git repo; plans there survive git operations anywhere but aren't version-controlled or shareable

Encountered 2026-04-22: wrote `harness-quick-wins-2026-04-22.md` to `neural-lace/docs/plans/`, hit the `.gitignore` at commit time, moved to `~/.claude/plans/` which is outside any repo.

Options to resolve:
- **Separate harness-dev repo:** e.g., `neural-lace-dev` or similar, tracking only the working plans/decisions/sessions for harness evolution. Isolates instance artifacts from shareable harness code.
- **Carve-out within neural-lace:** a `docs/internal-plans/` (not gitignored) specifically for harness-dev plans. Weakens the hygiene guarantee (contributors may leak identifiers), requires reviewer vigilance.
- **Accept `~/.claude/plans/`:** formalize this as THE location for harness-dev plans. Add a README there explaining the convention. Plans are local-only by design; cross-machine collaboration requires explicit git init + separate repo setup by the contributor.

Recommendation pending: option 3 (accept local-only) is cheapest and matches actual practice. Options 1-2 are correct for a growing contributor base.

### P2 — Bug-persistence gate should recognize cross-repo persistence

The `bug-persistence-gate.sh` hook scopes its check to the current project's `docs/backlog.md` or `docs/reviews/`. When trigger phrases reference harness-level concerns and persistence legitimately happens in the neural-lace repo, the hook still fires against the project cwd.

Two possible fixes:
- **Harness-aware scoping:** check both the current project's `docs/` AND `~/claude-projects/neural-lace/docs/backlog.md` when trigger phrases reference harness concerns (would require classifying trigger phrases as project-level vs harness-level)
- **Cross-repo persistence attestation:** explicit sentinel file (e.g., `.claude/state/persisted-elsewhere-<hash>.txt`) carrying the commit SHA of the cross-repo persistence; similar to the existing `--ack` pattern

Workaround pattern (used 2026-04-22): write a dated review file in the current project's `docs/reviews/` that points at the authoritative persistence location. Works but requires the agent to remember to do it.

### P2 — Pre-existing harness-mirror drift between `~/.claude/` and `adapters/claude-code/` (surfaced 2026-04-24)

While building the failure-mode catalog plan (`docs/plans/failure-mode-catalog.md`), the harness-maintenance diff loop surfaced 25 pre-existing files that DIFFER between `~/.claude/` and `adapters/claude-code/`, plus 4 files MISSING from the repo. The drift is unrelated to the catalog plan and was already present at branch base. Affected categories: 7 agents, 11 rules, 7 hooks/skills/templates. Until reconciled, the harness-maintenance diff loop produces a noisy baseline that masks new drift.

**Fix:** dedicated reconciliation pass — for each DIFFERS file, decide which side is canonical (the live `~/.claude/` typically reflects the most recent thinking) and re-mirror. For the 4 MISSING files (`templates/completion-report.md`, `templates/decision-log-entry.md`, `skills/pt-implement.md`, `skills/pt-test.md`), copy to the repo. Then the diff loop returns clean and any future drift is immediately visible.

### P2 — capture-codify: detect FM-NNN-cited-but-doesn't-exist (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 6 ("Observability gaps"). Currently when a PR's mechanism field selects answer form (a) "Existing catalog entry" and cites `FM-NNN`, neither the CI workflow nor the local pre-push hook checks whether `FM-NNN` actually exists in `docs/failure-modes.md` at PR open time. A typo (`FM-001` vs `FM-100`) or a stale citation slips through silently — the PR passes the validator but the cite is dangling.

**Proposal:** extend the validator library (`.github/scripts/validate-pr-template.sh`) to optionally cross-reference any `FM-\d+` substring in the (a) section against `docs/failure-modes.md` headings (`^## FM-\d+`). On miss, emit a soft warning (`[pr-template] WARN: cited FM-NNN not found in catalog`) without failing the check — reviewer responsibility for now, but the warning makes the gap visible. Hard-fail later if false-positive rate is low.

**Effort:** ~1 hour (single regex addition, self-test cases for hit/miss/no-cite). Existing validator structure makes this trivial.

### P2 — capture-codify: answer-form distribution telemetry (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 6. The mechanism field has three answer forms (a / b / c). Tracking the distribution over time would surface meaningful patterns: a sudden spike in (c) "no mechanism" answers signals discipline drift; a steady stream of (b) "new entry proposed" with no follow-up catalog growth signals a broken capture-codify cycle.

**Proposal:** extend `adapters/claude-code/scripts/audit-merged-prs.sh` to count (a/b/c) selections per PR and emit a distribution summary alongside the per-PR PASS/FAIL output. Optionally feed the counts into the weekly `/harness-review` skill's compliance section.

**Effort:** ~2 hours. The validator library already detects answer-form selection in `detect_answer_form()`; surfacing it from the audit script is a single counter loop.

### P2 — capture-codify: pre-commit atomicity gate for template ↔ validator edits (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 7 (failure-mode row "Accidental template-file edit"). The validator library expects specific section headings and placeholder text in `.github/PULL_REQUEST_TEMPLATE.md`. If a maintainer edits the template (e.g., changes wording while editing nearby files) without updating the validator's regex constants, the validator silently breaks — the next PR after the edit fails CI unexpectedly with a confusing message.

**Proposal:** new pre-commit hook `template-validator-atomicity-gate.sh` that detects when `.github/PULL_REQUEST_TEMPLATE.md` is staged AND `.github/scripts/validate-pr-template.sh` is NOT staged in the same commit; blocks with a stderr message naming the rule. Mirror of the existing `decisions-index-gate.sh` atomicity pattern.

**Effort:** ~3 hours. Existing atomicity gate (`decisions-index-gate.sh`) is a direct template; copy + adapt regex + write self-test.

## Existing entries

## ✅ DELIVERED 2026-04-20 — Mechanical enforcement of bug-persistence rule

Shipped in commit `0090d4b`: `hooks/bug-persistence-gate.sh` Stop hook wired into `settings.json.template`. Scans session transcript for trigger phrases, checks `docs/backlog.md` + `docs/reviews/` for persistence, blocks session end if bugs mentioned without being recorded. Attestation escape hatch via `.claude/state/bugs-attested-*.txt`. Documented in `docs/harness-architecture.md`.

## P1 — Consolidated findings rollup on session end

Related to the bug-persistence hook: a skill or helper that, at session end, reads all `docs/reviews/YYYY-MM-DD-*.md` files + recent git log for `docs/backlog.md` changes, and produces a single `docs/sessions/YYYY-MM-DD-session-summary.md` cataloging every finding + its disposition (fixed in commit X / deferred to backlog entry Y / invalid).

## P1 — Hardening of existing self-applied rules

Several rules in `~/.claude/rules/` are Pattern-level (no hook enforcement) and depend on agent discipline. Audit them for which ones are violated most often in practice, and propose Mechanism-level enforcement (hook / schema / assertion) for the top offenders. Candidates from observation:

- `planning.md`'s "Identifying a gap = writing a backlog entry, in the same response" — violated on 2026-04-20
- `orchestrator-pattern.md`'s "Main session dispatches, doesn't build directly" — violated when main session is tempted by small edits
- `testing.md`'s "E2E testing after system-boundary commit" — often skipped when under time pressure

## P0 — Stop hook for "narrate-and-wait" pattern (new 2026-04-21)

Counterpart to bug-persistence-gate: catch the pattern where the agent
completes a unit of work, narrates a summary, and implicitly stops
waiting for user confirmation. Specifically blocks session termination
when the last N assistant turns contain trigger phrases like "next up
is", "ready to continue", "want me to proceed", "after merge", "then
I'll" — indicating the agent has queued up work it could be doing now
but is pausing to announce.

Scope ~3 hrs: Stop hook script, transcript regex, allowlist for genuine
end-of-session summaries (e.g., "done for tonight", explicit /clear
requests, explicit "stop" from user).

This was added after the maintainer repeatedly observed the agent
stopping mid-execution on 2026-04-21 and asking rhetorical "are you
still working?" questions.

---

## HARNESS-GAP-15 — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-4-gap-15-cleanup.md` (sub-items A/B/D/E/F; sub-item C deferred to next master merge)

(Historical entry preserved below for context.)

## HARNESS-GAP-15 — Phase 1d-E public-release-hardening + harness-quick-wins audit-cleanup (added 2026-05-04)

**Source.** 2026-05-04 stale-plan audit. Three plans were marked COMPLETED but two had falsely-complete state (the third — `document-freshness-system.md` — verified ACTUALLY COMPLETE and stays archived). The two that were prematurely marked are now flipped back to ACTIVE; this gap aggregates their resolution paths with related Phase 1d-E hygiene work into a single rollup so they ship as one focused phase.

**Sub-items (P2 unless noted):**

**A — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit f112226). Scanner self-test repaired; assertion flipped to exit 1 on `docs/plans/foo.md`; two new assertions added for the allow-list behavior. Self-test PASS today.

**B — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit f112226). Scanner exemption tightened: directory-level exemption applies ONLY to non-allow-listed paths within `docs/decisions/`, `docs/reviews/`, `docs/sessions/`. Committed allow-listed files (`NNN-*.md`, `YYYY-MM-DD-*.md`) ARE scanned. Full-tree scan after the fix correctly reports 15 codename hits in committed decision/review files — these are the pre-existing leakage tracked in sub-item C below.

**C — Codename scrub from feature-branch commits before next master merge (P2, deferred).** Public feature branches currently contain identifying codenames + the maintainers GitHub usernames in tracked decision/review files. Specific identifiers redacted from this entry per the hygiene-scan denylist; see the 2026-05-04 audit conversation transcript for the actual strings. **Right-sized severity: P3 distribution-readiness/hygiene concern, NOT a security incident** — no credentials/tokens/secrets in the leak; identity-correlation already trivially derivable from public commit author fields. Cleanup approach: at next master-merge time, scrub the merging diff of identifiers OR rebase the merging branch through orphan-commit (Phase 8 pattern). Force-pushing the public feature branch is rejected per the right-sized threat model — unnecessary urgency. Effort: ~1 hr per merge; integrates with normal merge workflow.

**D — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit 22c0e65). Schema authored at `adapters/claude-code/schemas/automation-mode.schema.json` per the original Task 6.1 spec — `{version, mode, deploy_matchers}` with version: 1 sentinel matching the existing four schemas. Validates against the example.json that already shipped.

**E — IMPLEMENTED 2026-05-04 via Phase 1d-E-4.** `public-release-hardening.md` flipped to COMPLETED; auto-archived. Honest annotations on the four previously-unchecked tasks: 1.2 scoped down per Option A; 4.2 shipped via HARNESS-DRIFT-02; 5.3 deferred with rationale; 6.1 shipped in commit 22c0e65. Plan file is gitignored, but the audit closure section is preserved in working tree.

**F — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit ff5717d). `harness-quick-wins-2026-04-22.md` flipped to COMPLETED; auto-archived. Phase A Task 1 deferred with rationale: per-project `effort-policy-warn.sh` covers most of the value; global default flip is a personal-cost change that should happen interactively. 17 of 18 tasks remain shipped.

**G — Phase 1d-E rollup (HARNESS-GAP-14 + HARNESS-GAP-15 + HARNESS-GAP-10 sub-gaps A/B/C/F/G/H + HARNESS-GAP-13).** When Phase 1d-E is planned, bundle these into a single coherent plan so the audit-cleanup work ships as one phase with one shared verification pass.

**Effort estimate.** S-M for A/D/F individually; M for B (depends on what new findings the tightened scanner surfaces); incremental cost for C (zero now, ~1 hr at next merge); A+B+D+E+F together: ~4-6 hr of focused work. G is the planning step, ~30 min.

**Class.** `falsely-marked-complete-plan` (sub-class of `stale-state-claim`). The 2026-05-04 audit caught the pattern; the resolution path here closes the specific instances + restores the post-conditions the plans claimed.

**Cross-references.**
- Audit findings: this session's transcript (2026-05-04 conversation about stale plans)
- The two un-archived plans: `docs/plans/harness-quick-wins-2026-04-22.md`, `docs/plans/public-release-hardening.md`
- The third plan (verified complete, stays archived): `docs/plans/archive/document-freshness-system.md`
- Companion gaps: HARNESS-GAP-14, HARNESS-GAP-13, HARNESS-GAP-10 sub-gaps A/B/C/F/G/H

## HARNESS-GAP-35 — Dispatch worktree teardown + reuse is Anthropic-side; the in-our-control mitigation shipped (added 2026-05-17)

**Priority:** P2 (the recurring cleanup is now automatable; the upstream gap is tracked, not actionable by us)

**The gap.** The Claude Code desktop-app Dispatch / "+ New session" flow
creates a sibling git worktree per code task
(`~/claude-projects/<project>/<adjective-name-hash>`, branch
`claude/<same>`). Nothing — neither the Anthropic runtime nor this
harness — removes that worktree when the Dispatch session ends, and there
is no mechanism for a new session to reuse an idle merged-out worktree.
The spawn logic lives in the Anthropic desktop app / Claude Code runtime
and is not exposed to us. Result: unbounded accumulation (observed
2026-05-17: ~50 in one repo, ~30 in neural-lace; new worktrees appeared
mid-session during the cleanup, confirming it's live and ongoing).

**Shipped this session (the in-our-control half):**
`adapters/claude-code/scripts/worktree-prune.sh` — conservative periodic
pruner (removes only fully-merged + clean + ≥3d-idle + unlocked +
non-current; session/build noise filtered; `--self-test` PASS; mirrored
to `~/.claude/`). One cleanup pass removed ~47 provably-safe worktrees.
Full lifecycle analysis + per-item surface list +
proposal-ranked-by-feasibility in
`docs/reviews/2026-05-17-dispatch-worktree-accumulation.md`.

**Open sub-items:**
- **A (Misha action, ~1 click):** create the `worktree-prune-weekly`
  scheduled task (cron `0 9 * * 1`; spec in the review doc) OR a Windows
  Task Scheduler entry running `bash ~/.claude/scripts/worktree-prune.sh
  --apply --repo <main>...` weekly. Blocked from automation here because
  `mcp__scheduled-tasks__create_scheduled_task` requires interactive
  approval (unavailable in unsupervised mode).
- **B (upstream ask, not actionable by us):** if/when the desktop app
  exposes a Dispatch session-end hook or a worktree-reuse setting, wire
  auto-cleanup / reuse. Until then the periodic pruner is the answer.
- **C (manual review):** ~13 orphaned `worktree-agent-*` orchestrator
  worktrees in one downstream repo (2026-04-20…04-30) — likely
  squash-landed weeks ago; spot-check content-in-master then `--force`
  remove (or
  `worktree-prune.sh --include-locked --age-days 14` after spot-check).
- **D (Misha decision):** the salvageable/unmerged worktrees surfaced
  individually (see review doc §4) — salvage vs discard per item.

**Cross-references.** `docs/reviews/2026-05-17-dispatch-worktree-accumulation.md`
(full analysis), `adapters/claude-code/scripts/worktree-prune.sh` (the
shipped fix), `docs/harness-architecture.md` Scripts table, companion
HARNESS-GAP-28 (Dispatch spawner env-var convention — same "spawn is
Anthropic-side" theme).

---

## HARNESS-GAP (2026-06-02): broadcast-active-session.sh cannot parse SSH host-alias origin URLs

**Severity:** P1 (cross-machine coordination silently non-functional on alias-routed remotes)
**Found:** Office_PC bootstrap session, 2026-06-02. PROVEN.
**Symptom:** `broadcast-active-session.sh write` exits 1 with `ERROR: could not parse origin URL`; no `harness/active-sessions/<host>` branch is created on the PT-org remote (verified 404 via `gh api repos/<pt-org>/<repo>/branches/...`).
**Root cause:** `_origin_owner_name()` `case` only matches `https://github.com/*` and `git@github.com:*`. This machine's origin push URL is `git@<ssh-alias>:<pt-org>/<repo>.git` — an SSH host alias (`Host <ssh-alias>` in ~/.ssh/config selecting a per-account key). The alias != `github.com`, so the parser returns empty -> `_die`. `gh api` itself works (active gh account has org push); only owner/name extraction fails.
**Status:** FIXED 2026-06-03 (commit on neural-lace master; broadcast verified writing to the PT-org remote).
**Fix (strict superset; cannot regress github.com parsing):** add an arm to `_origin_owner_name()` handling `git@<alias>:owner/name(.git)`:
    git@*:*/*) url="${url#git@*:}"; url="${url%.git}"; printf '%s' "$url" ;;
  (place before the catch-all `*)`; also covers https with custom host via an analogous `https://*/*/*` arm if desired.)
**Propagation:** master-wins via session-start-auto-install.sh -> fix must land in canonical adapters/claude-code/scripts/ + be pushed; a live-only patch is reverted on next session start.

---

## HARNESS-GAP (2026-06-02): decision-context-gate schema path broke on conversation-tree-ui -> workstreams-ui rename

**Severity:** P1 (decision-context enforcement substrate non-functional after the rename)
**Found:** Office_PC bootstrap session, 2026-06-02. PROVEN.
**Symptom:** `decision-context-gate.sh` BLOCKS every decision-soliciting Stop message even when a well-formed `::: decision id=... :::` fence is present. The gate's `_resolve_schema_module()` looks for `<root>/neural-lace/conversation-tree-ui/state/decision-context-schema.js` and `<root>/conversation-tree-ui/state/decision-context-schema.js`, but the repo renamed `conversation-tree-ui` -> `workstreams-ui`; the schema module is no longer at either path in the main tree (only in stale `.claude/worktrees/*`). The Zod validator can't load -> no fence ever validates -> the gate blocks unconditionally. Compounded when cwd is non-git (git-root resolution fails, falls to a `_fallback_conv_tree_path` that also misses).
**Fix:** update `_resolve_schema_module()` in `adapters/claude-code/hooks/decision-context-gate.sh` to point at `workstreams-ui/state/decision-context-schema.js` (keep the old path as a fallback for back-compat). Sweep the whole gate (and any sibling hooks: `workstreams-*`, `decision-context-*`, `_fallback_conv_tree_path`) for other `conversation-tree-ui` literals left stale by the rename — likely a class, not a single instance.
**Workaround:** per-session `.claude/state/decision-context-waiver-<ts>.txt` (the gate's documented escape).
**Propagation:** master-wins via auto-install; fix must land in canonical + be pushed.

---

## HARNESS-GAP (2026-06-03): decision-context node-validation layer broken on Windows (MSYS path) + module deps never installed

**Severity:** P2 (down from P1 — gate core verified working after fixes; residual is self-test + GUI-emission edge cases)
**Found:** Office_PC bootstrap, 2026-06-03. Compounds the 2026-06-02 rename entry above.
**Sub-bug A — module deps never installed (REAL):** `neural-lace/workstreams-ui/package.json` declares `zod` but nothing `npm install`s it; `install.sh` does not install the module's deps. A fresh machine has no `node_modules`, so `require('zod')` in the schema fails → gate can't validate fences. **Fix (REMAINS):** `install.sh` should run `npm install --omit=dev` in `neural-lace/workstreams-ui/` (idempotent), so every machine self-provisions. Manually installed zod this session as a stopgap (so this machine's gate works now).
**Sub-bug B — MSYS-vs-Windows node path (REFUTED 2026-06-03):** initial hypothesis was that the gate passes MSYS `/c/...` paths to the Windows node binary and node can't resolve them. **This is FALSE.** Git Bash/MSYS auto-converts path-shaped *command arguments* to Windows form (`C:\...`) when invoking native binaries, and the gate passes all paths as `process.argv` args (not embedded in the `-e` string). Verified: `node -e "require(process.argv[1])" "/c/...schema.js"` LOADS; the validator (`safeValidateFence`) loads + correctly rejects invalid payloads with zod errors; `state.js` loads. Do NOT implement a cygpath fix — there is no path bug.
**Verified gate behavior (e2e, this session):** decision-soliciting prose WITHOUT a fence → `{"decision":"block"}` (correct); neutral message → exit 0 allow (correct). So the user-facing block/allow path WORKS post-fix.
**Status:** rename-sweep FIXED (commit 4031d6a) + zod installed (stopgap) → gate core FUNCTIONAL. REMAINS: (1) `install.sh` npm-install so other machines self-provision; (2) self-test 16/10 residual in invalid-fence-rejection + GUI-emission (`appendEvent` to GUI state) assertions — focused follow-up, not user-facing-blocking.

---

## HARNESS-GAP (2026-06-03): workstreams GUI shows no live data — emit/wiring/data-model defect cluster

**Severity:** P2 (the GUI server works + serves state; the data pipeline feeding it is broken, so the GUI shows project roots with "nothing in flight")
**Found:** Office_PC session, 2026-06-03, launching the workstreams GUI. The server (`workstreams-ui/server/server.js`, port 7733) is healthy and `/api/state` returns 55 nodes — but all "open" nodes are duplicate roots/person nodes, so the GUI's per-project "in flight" view is empty.
**Cause A — emit crash on empty stdin (FIXED this session):** `workstreams-emit.sh` `_run_on_session_start` declared `local sid source cwd transcript_path` then only assigned them inside `if [[ -n "$input" ]]`; with empty stdin, `$sid` was referenced unset → `sid: unbound variable` under `set -u` → no emit. Fixed by initializing the vars to "". (Other handlers use the always-assigned `_session_id "$input"` pattern — class-checked, no siblings.)
**Cause B — stale settings wiring (NOT fixed):** live `~/.claude/settings.json` SessionStart wires the OLD `conversation-tree-emit.sh --on-session-start`, which writes to the OLD `conversation-tree-ui/state/tree-state.json` (373-node stale snapshot). The current server reads `workstreams-ui/state/tree-state.json`. So live sessions emit to a file the GUI never reads. The settings.json additive-merge can't fix this (it never REPLACES the old entry — coarse-grained compound-entry skip). Fix: swap `conversation-tree-emit.sh` -> `workstreams-emit.sh` (and the sibling gates `conversation-tree-{state,stop}-gate.sh` -> `workstreams-{state,stop}-gate.sh`) across SessionStart/Stop/PreToolUse in live settings + the template. Part of the broader HARNESS-GAP-14 settings-reconciliation.
**Cause C — duplicate-root data model (NOT fixed):** even when `workstreams-emit.sh` runs, it appends duplicate project-root/person nodes ("neural-lace" x2, "misha" x4 observed) rather than de-duplicating to a stable root + nesting a single session branch under it. So the GUI groups by project but finds no real in-flight work-item children. Needs investigation of the emit's node-id derivation + `_project_root` de-dup + the snapshot reducer's parent-linkage.
**Status:** Cause A FIXED (commit pending). Causes B + C REMAIN — a workstreams-ui pipeline repair (settings-wiring swap + emit de-dup/nesting), scoped separately from the harness-gate-fixes plan.

## HARNESS-GAP-52 (2026-06-13): harness-hygiene-scan.sh no-ops in every downstream/product repo

**(absorbed by docs/plans/nl-overhaul-program-2026-07.md — B.3)**

**Severity:** P1
**Found:** downstream-product SMS-debug session, 2026-06-13 (operator: "harness-hygiene-scan is supposed to run on every repo that uses the harness").
**Verified:** `harness-hygiene-scan.sh` resolves its denylist at `$REPO_ROOT/adapters/claude-code/patterns/harness-denylist.txt` and `exit 0` (silent skip) when absent (hook lines ~319-322). That path exists ONLY in the neural-lace harness repo, so the scanner NEVER runs in any downstream/product repo. The rule's stated "every repo using the harness" intent is unmet.
**Tension:** the denylist keeps the KIT generic (no project identifiers IN the kit); on a product repo, project identifiers are legitimate, so the kit-denylist cannot run as-is there. PII/secret coverage for all repos currently lives in `pre-push-scan.sh` (global `core.hooksPath`), which DOES run everywhere.
**Fix (needs design):** either (a) resolve the denylist from the installed `~/.claude/patterns/` as a fallback AND run only the PII/heuristic layer (not the kit-identifier denylist) on product repos; or (b) explicitly scope harness-hygiene-scan kit-only and move "protect every repo" wholly to `pre-push-scan.sh` with documented PII patterns + a clear rule. Reconcile with pre-push-scan PII coverage; add self-tests for the product-repo path.
**Originating incident:** operator PII (personal cell) committed to a downstream product repo (its PR #510), NOT caught by any local hook — only GitHub server-side secret-scanning surfaced it.

## HARNESS-GAP-53 (2026-06-13): completion-criteria-gate "deploy" criterion is presence-only, not prod-verified

**(absorbed by docs/plans/nl-overhaul-program-2026-07.md — D.4)**

**Severity:** P1
**Found:** same session.
**Defect:** the Stop-hook completion-criteria-gate passes the "deploy" criterion on any deploy-evidence token in the final message; it does NOT verify a PRODUCTION deployment exists for the merged commit SHA. An agent can honestly cite a PR PREVIEW deploy ("Vercel — Deployment has completed") and pass while NOTHING reached production.
**Observed:** a multi-fix downstream-product session merged to master with the gate passing "deploy ✓" while production ran a 23h-old build (master→prod auto-deploy was broken — see that repo's DEPLOY-MASTER-NOT-REACHING-PROD-01 backlog entry). No fix was actually live; the gate gave false assurance.
**Fix:** strengthen the deploy criterion to require/verify a production deployment whose commit == merged SHA (checkable artifact: prod-alias commit == HEAD), or require an explicit prod-verification step (`vercel ls --prod` / prod-alias commit check) rather than accepting any deploy token. Pair with a "PR Vercel checks are PREVIEW, not prod — verify don't assume" reminder.

## NL-ISSUES-TRIAGE-20260705 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 6 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 0d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260706 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 7 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 1d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## HARNESS-GAP-54 (2026-07-06): PreToolUse blocking-intent hooks that cannot block (exit-1 wiring class)

**Found:** hygiene-remediation session 2026-07-06 (worktree sweet-hamilton), investigating why a live `git commit` touching a denylist-matching manifest.json did not visibly block.
**PROVEN (pre-commit chain, fixed same day):** the template wired `bash ~/.claude/hooks/pre-commit-gate.sh || exit 1`; Claude Code PreToolUse hooks block only on exit code 2 — any other non-zero is non-blocking (stderr to user pane, tool call proceeds). Differential evidence, same session: scope-enforcement-gate.sh (exits 2) blocked a probe commit; pre-commit-gate.sh invoked directly caught a staged denylist token (RC=1) — yet real commits passed.
**Fix drafted but DEFERRED (decide-and-go, 2026-07-06):** the flip is one character (template line 301 `|| exit 1` → `|| exit 2`); harness-reviewer verdict CONDITIONAL-PASS (record: docs/reviews/2026-07-06-pre-commit-chain-exit2-review.md). NOT shipped in the remediation commit because dry-runs against the real workflow found the chain's plan-reviewer sub-gate latent-RED on the ACTIVE program plan itself (Check 1 undecomposed-sweep fires on 7 completed `- [x]` task lines plus the unchecked E.7 line) and on every spec appendix (missing `## Goal`/`## Scope` — they are REFERENCE appendices, not plans; Check-10 headers fixed in this commit). Flipping now would hard-block every program checkbox-flip commit: a known-FP storm, worse trust erosion than the documented gap.
**Activation preconditions (flip ships when ALL hold):** (1) plan-reviewer gains a `Status: REFERENCE` skip (convention exists since specs-b/c) and Check 1 evaluates only unchecked `- [ ]` tasks (its purpose is decompose-BEFORE-start; retroactive decomposition of verifier-passed work is pure FP) — both changes via harness-reviewer; (2) E.7's task line is Check-1-clean or decomposed; (3) every FRESHNESS_GATES block message swept for remedies that actually work under PreToolUse semantics (hygiene-scan's stale `--no-verify` suggestion fixed in this commit; reviewer flagged the class); (4) GAP-55 sweep or a structured session-time waiver for hygiene-scan's residual-match FP surface (reviewer Major: whole-file scan × ~70 residual files × no waiver = blocks sessions for debt they didn't create).
**Residual theater subclass (reviewer sweep, PROVEN):** beyond the five inline template guards (lines ~20/~29/~128/~137/~146 — which also read legacy `$CLAUDE_TOOL_INPUT`; if that env var is unpopulated they never fire at all), three wired+blocking:true+PreToolUse hook scripts exit 1 on their block paths: no-test-skip-gate.sh, plan-deletion-protection.sh, wire-check-gate.sh. Suspects: automation-mode-gate.sh, env-local-protection.sh, migration-naming-gate.sh, plan-edit-validator.sh. Audit every wired+blocking+PreToolUse manifest entry's block-path exit code, not a hand-picked list: `jq -r '.entries[] | select(.wired_template and .blocking and (.events|index("PreToolUse"))) | .hooks[]' adapters/claude-code/manifest.json | xargs -I{} sh -c 'grep -L "exit 2" adapters/claude-code/hooks/{}'`
**Fix shape:** wrapper-aware doctor check — for every manifest `blocking: true` wired hook, assert the TEMPLATE wiring maps failure to exit 2 (bare invocation of an exit-2 script, or an `|| exit 2` wrapper); message-text heuristics are insufficient (the defective wrapper carries no BLOCKED text of its own). Migrate the five inline guards to stdin-JSON + exit 2 with per-gate FP review. Until the flip lands, manifest `pre-commit-chain.blocking: true` remains a documented-false claim — this entry IS the §10 marking.

## HARNESS-GAP-55 (2026-07-06): full-tree hygiene debt (~70 residual matches) + public-mirror exposure

**Found:** same session. GAP-13 closure (2026-05-05) recorded full-tree ZERO matches; 2026-07-06 `--full-tree` = 82. Twelve fixed same day (manifest golden_scenario, doctor self-test fixture, spawn-worktree evidence path redaction, specs-f + status-review prose). Root cause of silent accretion: GAP-54 (local gate non-blocking) + CI scans changed-files-only and direct-to-master pushes only get a post-hoc red X (branch protection gates PRs, not pushes) — the last two master pushes were already red on the Harness-hygiene job (runs 28806487530, 28807532161).
**Exposure:** the personal mirror repo is PUBLIC (verified anonymously 2026-07-06) and tree-synced, so residual matches (org/account identifiers, product codenames in ops docs and workstreams-ui scripts, personal paths in archived docs) are visible now; ALL past matches remain in public git history regardless of HEAD fixes. History purge / mirror visibility is an operator decision — see NEEDS-YOU.md 2026-07-06.
**Operator ruling (2026-07-06): LEAVE** — the mirror is public by design; no visibility flip, no history rewrite. Triage rubric: benign → exempt with provenance note; genuinely private (credentials, PII, client identifiers, personal paths) → redact in the current tree; truly-private-in-history → NEEDS-YOU item, stop.
**Executed 2026-07-06 (same session, second commit):** 8 personal-path occurrences redacted in-tree (docs/conventions/worktree-per-session.md, decision 037, discoveries 2026-05-30 + 2026-06-03, status-redesign evidence ×2, reviews 2026-05-20 + 2026-06-02); benign org/account/product references exempted file-by-file in is_exempt() with a provenance-note block (16 repo-architecture docs + archive twins for the two synthetic-ci plans); `neural-lace/{workstreams-ui,conversation-tree-ui}/scripts/` added to the existing instance-tooling exemption class; `.gitattributes` added to the heuristic-only (Layer-2) exemption. Full-tree scan 70 → 0. Denylist itself unchanged — NEW files are not exempt and face full scrutiny.
**Still open:** (a) revive GAP-13 Layer-3 (periodic full-tree audit) so drift cannot silently accrete again — pairs with the GAP-54 activation work; (b) test-credential question — see the AUDIT below, superseding the earlier "in history" framing.

**Test-credential AUDIT (2026-07-06, read-only forensics — corrects the earlier framing):** the two tokens are NOT a leaked live secret in neural-lace. Batched exhaustive scan of all 1,462 commits (`git rev-list --all | xargs -n150 git grep -lI`) plus pickaxe (`git log --all -S`) plus current-tree grep all agree: both tokens exist in exactly ONE file ever — `adapters/claude-code/patterns/harness-denylist.txt`, the block-list itself — introduced at fa50661 and never in any code/config/env/fixture. A case-insensitive `pipeline.?test` sweep of the whole tree (minus denylist) returns zero; `~/.claude/local/credentials-reference.md` does not track this account. So in this repo the value is the DEFENSIVE PATTERN, not a leak. The ONE residual concern is operator-owned and can't be answered from this workspace: is the `pipeline-test@…` account still live with that password in the downstream product's auth (Supabase)? (full identifier in the gitignored NEEDS-YOU.md, kept out of this tracked file per the denylist.) If dead → LOW; if live → HIGH, because (see GAP-56) the denylist is public and serves the plaintext. Tracked in NEEDS-YOU.md 2026-07-06 (DEAD / LIVE / CHECK-IT).

## HARNESS-GAP-56 (2026-07-06): shipped denylist self-discloses a literal secret value in a public file

**Found:** the test-credential audit above. `adapters/claude-code/patterns/harness-denylist.txt` is a TRACKED, PUBLIC-mirrored file, yet it contains one literal secret VALUE — the `PipelineTest…`-shaped password (line ~33). Verified anonymously readable now: the public mirror's raw `…/adapters/claude-code/patterns/harness-denylist.txt` → HTTP 200, contains the value. To block a literal string from recurring, harness-hygiene-scan.sh needs that literal in its pattern file — which, for a public denylist, inherently republishes it. Self-defeating for secret VALUES (fine for non-secret identifiers like usernames/org names, which are the file's other literals and are inherently public).
**Class:** control-that-discloses-what-it-guards. `PipelineTest…` is the only literal secret value in the file; everything else is a generic regex shape or a public identifier.
**Fix shape:** literal secret VALUES belong in the per-machine gitignored layer that the git-native `adapters/claude-code/git-hooks/pre-commit` already loads (`$HOME/.claude/business-patterns.d/*.txt`), NOT in the shipped public denylist. Options: (1) move the password literal to `~/.claude/business-patterns.d/` and delete it from the public denylist — but then harness-hygiene-scan (which reads only the repo denylist) no longer blocks it; reconcile by having harness-hygiene-scan also source a local overlay; (2) block by a non-reversible representation (store a hash, match against hashes) so the public file never carries the plaintext; (3) accept as-is IF the account is confirmed DEAD (then it is an inert string, not a secret). Decision gated on the NEEDS-YOU liveness answer. Harness-reviewer before any denylist-mechanism change.
**AUDIT RESOLVED (2026-07-06, verified from downstream-product code + git + schema, not assumed):** the account is a Playwright/e2e pipeline test user in the downstream product repo (setup + verify scripts still in that repo's HEAD; introduced 2026-04-07, repo active through 2026-06-28). Created as `role: 'admin'` but confined by that product's org-isolated RLS (`org_id = user_org_id()` on every table) to a single test org; it does NOT hold the separate `is_platform_user()` flag that gates cross-org/customer data — so an attacker using the credential gets an authenticated foothold in a test org only, not a path to customer data. Severity MEDIUM (live prod auth, public-guessable password, org-admin — but RLS-bounded). The real password carries a trailing char the public substring omits. Two caveats: any authenticated foothold in prod is unwanted, and one product migration (`…_sentiment_routing.sql`) has an open `USING(true)` policy (separate product-side finding to route to that product's backlog). One unverified fact — current existence + last_sign_in_at — the read-only prod Supabase query was correctly blocked by the auto-mode safety classifier (production auth, not pre-authorized); pending operator go-ahead. Full detail + remediation + the two operator asks in the gitignored NEEDS-YOU.md.
**FIX LANDED (2026-07-07, operator REMEDIATE-ALL):** took option 1 + machine-local layer. (a) Product repo de-hardcoded — `TEST_PASSWORD` read from env, no literal, product-repo PR #783 (green; scripts not run in CI → no pipeline break; link in NEEDS-YOU.md). (b) Literal relocated from this public denylist to `~/.claude/business-patterns.d/pt-test-credentials.txt` (git-native pre-commit blocks it machine-wide on every repo; proven end-to-end); harness-reviewer PASS-conditional (record inline in commit). **Accepted scope delta (reviewer Major):** harness-hygiene-scan.sh + both CI jobs read ONLY the repo denylist, so the SERVER-SIDE/CI block on the password VALUE is dropped by the relocation — accepted because the credential is being rotated dead; if the pending liveness check returns LIVE, add a CI-side backstop for the value. **NOT fully closed:** gated on the operator rotating the Supabase account (NEEDS-YOU.md) and the DEAD/LIVE confirmation. Remaining harness follow-up: optionally teach harness-hygiene-scan.sh to also source the local overlay (restores local-scanner parity; does NOT restore CI coverage — harness-reviewer-gated).

## HARNESS-PERF-O3-HB (2026-07-08): `nl status` per-session subprocess-fork density is now the dominant remaining `nl status` hotspot, not `find`

**Found:** build/wave-o-hb-perf task (O.3 heartbeat-lib sibling-find fix, commit a524474). Task scope was eliminating `hb_classify`'s own unindexed per-session full-tree `find` (session-heartbeat-lib.sh's `_hb_find_transcript`, duplicated against observability-derive.sh's already-indexed `_od_find_transcript`) — done, self-test-proven (a find-call counter asserts zero calls when the caller passes a pre-resolved path).
**Measured (this task, EPOCHREALTIME-timed, real $HOME/.claude estate — 34 heartbeats / 305 transcripts):** looping `hb_classify` over every real heartbeat file with NO transcript-path arg (pre-fix call shape) cost 12.458s wall; the SAME loop with the path pre-resolved via the O(1) index cost 11.563s wall. The `find`-specific share is ~0.9s of that 12.5s — direct per-call profiling attributes the bulk (~0.24-0.4s per heartbeat file, ~10-13s total across 34 sessions) to `_hb_field` (jq subprocess ×2/call, ~0.06-0.09s each), `_hb_epoch` (date subprocess, ~0.04s), and `_hb_pid_alive` (kill/ps, ~0.02s) — each a real Windows/Git-Bash process fork, all INSIDE `hb_is_stale`/`hb_classify`, independent of transcript resolution.
**Why out of scope for a524474:** od_sessions already extracts marker/branch/worktree/cwd/last_activity_ts from each heartbeat file in ONE jq call, and already knows `sid` (the loop variable) — `hb_is_stale`/`hb_classify` currently re-derive `session_id` and re-parse `last_activity_ts` from the file themselves via their own `_hb_field` calls, fully redundant with data the caller already has. Threading those through (an optional pre-resolved-fields signature, mirroring `_od_session_last_activity`'s existing 3rd-arg pattern) would close this gap, but changes `hb_is_stale`/`hb_classify`'s signature further than the "surgical, transcript-path-only" fix this task was scoped to — a session-heartbeat-lib.sh change of that shape needs its own task + harness-reviewer pass given it is the single shared C1 read-side oracle three callers depend on (session-heartbeat.sh sweep, harness-doctor.sh heartbeats-fresh, od_sessions).
**Fix shape (next task):** add optional pre-resolved-`session_id`/`last_activity_ts` args to `hb_is_stale`/`hb_classify` (same argument-count-distinguishes-supplied-vs-omitted convention a524474 established for the transcript path), and have od_sessions pass its already-extracted values through — same pattern, one more field pair. Re-measure `nl status` after; the <10s target from the O.3/hb-perf tasks was NOT met on this machine's current dataset (15.3s/15.8s/15.8s post-a524474, down from 19.5s/20.2s/16.3s) specifically because of this different, un-indexed-by-nature bottleneck (subprocess-fork count, not tree-walk cost).

**RESOLVED (build/wave-o-hb-perf2, this task):** landed the fix shape above plus one reinforcing change. FIX A (fork batching): `hb_is_stale`/`hb_classify` gained optional pre-resolved args (session-id, last-activity-EPOCH — not just the ISO string, now/epoch, and pid), same argument-count convention; `observability-derive.sh` gained `_od_heartbeat_batch_build`, ONE `jq -n 'inputs | ...'` call over every heartbeat file in the directory (keyed by filename-derived sid, all-or-nothing — falls back to the untouched per-file loop if any heartbeat file is malformed), with the `last_activity_ts` epoch conversion done inside that same jq call via `fromdateiso8601` (zero extra forks). `od_sessions` now computes "now" once and threads every pre-resolved field through to `hb_classify`, so the common (live-heartbeat) case forks ZERO `_hb_field`/`_hb_epoch`/`date` subprocesses per session; `kill`/`_hb_pid_alive` already only ran for stale candidates (verified, not changed). Self-test proof: session-heartbeat-lib.sh Scenario 6f (file-based call counters — plain shell variables don't survive a command-substitution subshell boundary, learned the hard way mid-build) proves 0 `_hb_field`/`_hb_epoch` calls across fresh/mid-turn-live/crashed cases and exactly 1 `_hb_pid_alive` call for the crashed (stale-candidate) case; observability-derive.sh Scenario 2b shadows `jq` itself via a PATH shim and proves exactly 1 jq call for a 3-session estate AND for an 8-session estate (O(1), not O(N)). FIX B (reap hygiene): `session-heartbeat.sh reap [--json] [--reap-min <n>] [--dry-run]` removes heartbeat files whose last_activity_ts AND transcript mtime (or absence) are BOTH older than `OBS_HEARTBEAT_REAP_MIN` (default 1440min/24h), emitting one `ledger_emit "session-heartbeat" "reap" <detail>` line per reap with `session_id` set to the REAPED session (so `nl why <sid>` still answers "what happened to this session" post-reap) — self-tested (3 required cases: >24h-dead reaped, stale-but-recent-<24h NOT reaped, live NOT reaped) plus --dry-run/--json/env-override coverage. Not wired to a scheduled call-site in this task (3-file scope: session-heartbeat-lib.sh, observability-derive.sh od_sessions path, session-heartbeat.sh — no session-start-digest.sh/doctor changes) — a cron/digest tick invoking `reap` periodically is a clean follow-up. **Measured (this machine, real $HOME/.claude estate):** ran `reap` for real (10 of 34 heartbeats were >24h dead with no matching transcript, removed), then `time bash adapters/claude-code/scripts/nl.sh status` ×3 against the remaining 24-heartbeat/920-transcript estate: 3.875s / 3.916s / 3.817s — down from the 15.3s/15.8s/15.8s baseline above, comfortably under the <10s bar. harness-doctor.sh --self-test stays 78/78 (all six o6-obs-heartbeats-fresh scenarios, including subagent/midturn/red-names-sid, pass unchanged — that check calls `hb_classify` with its original 2-arg shape, untouched by this fix).

## NL-ISSUES-TRIAGE-20260707 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 9 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 0d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260708 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 26 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 2d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260709 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 27 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 2d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260712 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 22 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 5d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

- **BUILD-DOCTRINE-FEEDBACK-LOOP-01 — close or retire the Tranche-4 pilot feedback loop** (added 2026-07-12 from tranche-4 supersession audit; label: `build-doctrine`, `priority:medium`). The canonical pilot RAN 2026-05-07 (product repo gap-audit; state.yaml + friction file prove it) and produced 5 concrete floor-change proposals (product repo docs/sessions/2026-05-07-pilot-friction-run-1.md) that were never applied to build-doctrine-templates/ and are tracked nowhere else. Also: build-doctrine-roadmap.md row 4 still says "NOT STARTED" — false in substance (2 of 3 done-when clauses met). Action: apply-or-explicitly-retire the 5 proposals + fix the roadmap row. Forcing function for the keep/retire call on the dormant Build-Doctrine program (no operator statement since 2026-05-17).

- **BUILD-DOCTRINE-ORCHESTRATOR-FATE-01 — validate or delete build-doctrine-orchestrator/** (added 2026-07-12 from tranche-4 supersession audit; label: `build-doctrine`, `priority:low`). Single commit ever (8e843fb scaffolding), never pytest-validated, _TODO_PILOT_VALIDATE_ sentinels throughout, 2 months dormant; plausibly obsoleted by the worktree orchestrator-pattern (the harness's real orchestration route). Vaporware-prevention: validate it or delete it — don't let it sit.

## NL-ISSUES-TRIAGE-20260713 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 35 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 5d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260714 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 44 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 4d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260715 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 49 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 7d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01 — review-record verdict quotes are unverifiable (added 2026-07-16, harness-governance-batch task 2)

**Severity:** P2 (a named, honestly-documented control gap — the review-before-deploy gate's own honesty_rationale + docs/design-notes/review-record-primitive.md's Writer section both point here).

**Gap:** `write-review-record.sh capture --quote "<verbatim>"` requires the orchestrator to paste a substring of a reviewer agent's actual returned message, but nothing verifies the pasted quote came from a real reviewer invocation — zero `SubagentStop`/`TaskCompleted` capture hooks exist anywhere in this harness to retrieve the real transcript and diff it against the claimed quote. The record `docs/reviews/records/*.json` writes today is an audit + honesty anchor (a citable, timestamped, content-addressed artifact), NOT a deploy-path anti-fabrication control — the deploy gate (install.sh hard-block / session-start-auto-install.sh skip+warn) checks record EXISTENCE + content-match only and structurally cannot check whether the quoted verdict is genuine.

**Fix (not yet built):** a capture hook on `SubagentStop` (or `TaskCompleted` for Task-tool dispatches) that writes the reviewer agent's actual final message to a location `write-review-record.sh` can read back and diff against the claimed `--quote` at capture time — turning "the orchestrator says the reviewer said X" into "the transcript captured at dispatch time says X." `plan-evidence-reviewer` is a plausible extension point (it already spot-checks evidence blocks the same way).

**Cross-refs:** `docs/design-notes/review-record-primitive.md` (Writer + anti-fabrication residual section, Amendment C), `adapters/claude-code/manifest.json`'s `review-before-deploy` entry `honesty_rationale` field, `adapters/claude-code/doctrine/review-before-deploy.md`.

**Adjacent gap CLOSED (2026-07-30, `docs/plans/review-independence.md`):** a related but distinct gap — the orchestrating/authoring session being the ONE dispatching the reviewer AND writing its own PASS record (self-approval) — is now structurally prevented: `scripts/review-queue.sh claim` mechanically refuses when the claimant's session matches the enqueuer's, and `harness-doctor.sh`'s `check_review_reviewer_independence` REDs on matching git-commit authorship between a PASS record and its reviewed content. This does NOT close the gap above — a genuinely different session can still paste a fabricated quote; the two gaps are orthogonal (WHO reviews vs. IS the quote real) and this backlog item stays open for the second one.

## REVIEW-RECORD-SURFACE-EXCLUDES-CARRIERS-01 — install.sh + session-start-auto-install.sh themselves are not in their own gate's trigger surface (added 2026-07-16, harness-governance-batch task 2)

**Severity:** P3 (self-referential blind spot, low near-term risk — noticed while implementing, not fixed unilaterally since it would expand the architecture-reviewed Amendment A surface without a second review pass).

**Gap:** the review-before-deploy trigger surface (Amendment A) is `adapters/claude-code/{hooks/**/*.sh, scripts/**/*.sh, agents/*.md, config/**, manifest.json, settings.json.template, rules/**}` — `adapters/claude-code/install.sh` is a direct top-level file, not under `hooks/` or `scripts/`, so it is literally NOT in-surface. A future unreviewed edit to `install.sh` itself (e.g., someone weakening or removing the hard-block splice this task added) would not be caught by the gate it implements. `session-start-auto-install.sh` IS covered (it lives under `hooks/`).

**Fix (not yet built, needs its own review):** either move `install.sh`'s logic into a `scripts/`-resident script `hooks`-style entrypoint calls, or add a narrow, explicitly-reviewed surface carve-out for `adapters/claude-code/install.sh` specifically (not a broad top-level glob — that would re-widen the surface well past what Amendment A scoped).

**Cross-refs:** `docs/design-notes/review-record-primitive.md` Trigger surface section, `adapters/claude-code/install.sh`'s review-before-deploy splice.

## REVIEW-FINDING-FIX-GATE-COMMIT-EDITMSG-STALE-01 — review-finding-fix-gate.sh (and any pre-commit-gate.sh-chained gate) reads a stale commit message (added 2026-07-16, harness-governance-batch task 3)

**Severity:** P2 (a confirmed, reproduced correctness defect in an existing blocking gate — not hypothetical).

**Gap (PROVEN, reproduced empirically while building `evidence-before-fix-gate.sh`):** `pre-commit-gate.sh`'s `FRESHNESS_GATES` chain (`docs-freshness-gate.sh`, `decisions-index-gate.sh`, `review-finding-fix-gate.sh`, etc.) is invoked via a PreToolUse "Bash" wrapper that pattern-matches `git commit` in the tool's `command` string and runs `bash ~/.claude/hooks/pre-commit-gate.sh` — entirely BEFORE the real `git commit` subprocess executes. `review-finding-fix-gate.sh` reads `.git/COMMIT_EDITMSG` to get "the current commit's message," but a direct repro (`git commit -m "first"` then `git add x && git commit -m "second"` with a real `pre-commit` hook installed) shows `.git/COMMIT_EDITMSG` at pre-commit-hook time still holds `"first"` — the PREVIOUS commit's message, not the one about to be made. Git only (re)writes `COMMIT_EDITMSG` during the message-prep step, which happens AFTER `pre-commit` fires. So in production, `review-finding-fix-gate.sh`'s finding-ID-reference detection is silently evaluating the WRONG (stale, one-commit-lagged) message — it can miss a real finding-ID reference in the actual new message, or false-trigger on a stale one from the prior commit.

**Why not fixed here:** out of scope for harness-governance-batch task 3 (which built a NEW, unrelated gate). `evidence-before-fix-gate.sh` avoids the whole class by reading the command string directly (`CLAUDE_TOOL_INPUT`/stdin JSON `.tool_input.command`, same proven approach as `observed-errors-gate.sh`) instead of `.git/COMMIT_EDITMSG` — see that gate's header comment for the full repro and rationale.

**Fix (not yet built):** either (a) rewire `review-finding-fix-gate.sh` (and `docs-freshness-gate.sh`/`decisions-index-gate.sh`, though those two don't need the message so are unaffected) to receive the command string — e.g. `pre-commit-gate.sh`'s wrapper exports `$CMD` before dispatching, or pipes the original stdin through — or (b) extract the message via the same `_efg_extract_commit_message`-style command-string parsing `evidence-before-fix-gate.sh` uses, reading `CLAUDE_TOOL_INPUT` directly in `review-finding-fix-gate.sh` itself (would require converting it to an independent top-level PreToolUse entry, same as this task's gate, since the nested chain's stdin is already exhausted by the wrapper).

**Cross-refs:** `adapters/claude-code/hooks/evidence-before-fix-gate.sh` header comment (the reproduction), `adapters/claude-code/hooks/review-finding-fix-gate.sh`, `adapters/claude-code/hooks/pre-commit-gate.sh`. Filed via `nl-issue.sh` 2026-07-16 (same session).

## EVIDENCE-BEFORE-FIX-PROMOTION-01 — calibrate evidence-before-fix-gate.sh before promoting warn-mode to blocking (added 2026-07-16, harness-governance-batch task 3, harness-review REJECT remediation)

**Severity:** P2 (a named, tracked calibration gap — the gate's own manifest entry and doctrine file both point here; without this row the warn-mode posture has no forcing function to ever revisit it).

**Context:** `evidence-before-fix-gate.sh` (Directive 1, "the 5th lesson") was built blocking, then demoted to WARN-MODE the same day after `harness-reviewer` PROVEN two miscalibrations: (a) OVER-FIRE — `git log -400 --format=%s | grep -cE '^fix(\(|:)'` = 61/400 (~15%; the reviewer's own `-300` sample independently measured ~13%) of this repo's own commits match the trigger, and a manual skim shows the DOMINANT class is harness-maintenance / review-remediation fixes ("fix(review): address harness-review findings", "fix(wave-o): ..."), not incident-forensics-shaped bugs the gate's rationale actually describes; (b) SILENT FAIL-OPEN — the message-extraction parser missed glued `-m"..."`, `--message=`/`-m=`, multiple `-m` segments, and `--amend --no-edit` (fixed in the same remediation, see the gate's header comment for the parser-reach detail).

**Task:** run a calibration period, then decide whether to promote `blocking:false` → `blocking:true` in `adapters/claude-code/manifest.json`'s `evidence-before-fix` entry (and re-add `'evidence-before-fix': 'commit-boundary'` to `adapters/claude-code/scripts/blocking-budget-check.js`'s `UNIT_MAP` at the same time, since promoting back to blocking makes it consume a budget unit again).

**Method (the reviewer's own sweep):** `git log -N --format=%s` over a representative trailing window (N=300-400 has been the working sample size), bucket every `^fix(\(|:)` match into `{incident-shaped, review/audit-remediation, refactor/typo, other}`, report the total share and the per-bucket breakdown. Promote to blocking ONLY if EITHER (a) the over-fire class (non-incident maintenance/review-remediation fixes) is separable by a trigger refinement (e.g. excluding a `fix(review)`/`fix(wave-*)`-shaped scope, or requiring an incident/finding-ID reference for the gate to even apply), OR (b) a fresh measurement (post parser-reach fix) shows the over-fire class is acceptably rare. If neither holds, keep warn-mode and re-run the sweep at the next calibration checkpoint.

**Cross-refs:** `adapters/claude-code/hooks/evidence-before-fix-gate.sh` (header comment, WARN-MODE section), `adapters/claude-code/doctrine/evidence-before-fix.md` (PROMOTION CONDITION), `adapters/claude-code/doctrine/diagnosis.md`, `adapters/claude-code/manifest.json`'s `evidence-before-fix` entry (`honest_status`, `fp_expectation`).

## NL-ISSUES-TRIAGE-20260716 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 52 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 7d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260717 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 52 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 7d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260718 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 62 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 8d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## STRIPJSCOMMENTS-PARSER-01 — cockpit selftest comment-stripper class bug

**Severity:** P3 (test-infra correctness)
**What:** cockpit.selftest.js stripJsComments treats an unclosed `/*` inside a `//` line comment as a block-comment opener, silently swallowing subsequent code from parse checks. Instance defused at asks.js:585 (task 7); the CLASS remains.
**Fold-in:** redesign task 9 acceptance hardening, or next cockpit selftest task.
**Filed:** 2026-07-19, task-7 builder report (barred from backlog edits).

## INBOX-STALE-LINK-OUTCOME-01 — populate resolved-item when/outcome in stale-link renders

**Severity:** P3 (polish; safety property already holds — never blank)
**What:** Inbox (inbox.js:32-36) and Requests stale-link misses render the honest generic "resolved earlier" fallback; the C3 LAW names "resolved <when> — <outcome>". Needs a resolved-items retention window in the payload (or a ledger lookback) to populate specifics. Same pattern in both views — fix as one class.
**Fold-in:** cockpit follow-on polish or task-9 hardening round.
**Filed:** 2026-07-19, t4 verifier residual (conf 9 PASS otherwise).
## NL-ISSUES-TRIAGE-20260719 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 64 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 9d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260720 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 77 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 10d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260722 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 85 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 12d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## ROADMAP-FILTER-HIDDEN-COUNT-01 — project chip hides phases with NO "N hidden" disclosure (C4 violation)

**Severity:** P2 (trust: a filtered view is indistinguishable from an empty roadmap)
**What:** Operator-reported 2026-07-22: the Roadmap rendered "PHASE 1 OF 1" while 16 of 17 phases
existed, because a persisted `neural-lace` project chip filtered them out. The chrome showed only
"0 hidden (harness chores)" — which covers the CHORE filter, not the PROJECT chip. The operator
reasonably concluded the deploy had not landed.
**Why it matters:** the plan's own C4 law requires a filtered-empty state to NAME the filter +
show the hidden count + offer one-click clear. That law is implemented for harness-chores and NOT
for the project chip — so the most-used filter is the one with no disclosure.
**Fix:** render a hidden-count chip per ACTIVE filter (project chip, and any future facet), same
shape as the chores chip ("16 hidden (project: neural-lace) [clear]"). Generalize: every filter
that can remove items from a view must contribute to the disclosure line — audit the Requests and
Inbox views for the same gap.
**Root cause of the underlying emptiness (FIXED, d10343d):** plan `project` was read off
`linkedAsks[0].project`, so plans without a linked ask got `project:''`. Attribution now derives
from the plan's own repo path. The DISCLOSURE gap above is the separate, still-open half.

## NL-ISSUES-TRIAGE-20260723 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 89 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 16d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260724 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 92 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 16d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260725 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 96 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 18d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260727 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 103 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 20d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## ROADMAP-R11-CROSS-REPO-RETROFIT-PATCH-01 — apply a verified cross-repo parent-plan header

**Severity:** P3 (data-only, no code change).
**Finding (research-verified, not fabricated):** a genuine parent/child plan
family exists across two repos — master
`Circuit/docs/plans/2026-04-20-a2p-10dlc-multi-channel-consent.md` (slug
`2026-04-20-a2p-10dlc-multi-channel-consent`) and child
`pocket-technician-marketing/docs/plans/2026-04-23-a2p-campaign-resubmission.md`
(slug `2026-04-23-a2p-campaign-resubmission`). Evidence: the pt-marketing
plan's own text (~line 38-40) explicitly defers scope to "circuit/docs/plans/
2026-04-20-a2p-10dlc-multi-channel-consent.md"; the Circuit plan's scope
section explicitly names the pocket-technician-marketing repo's form-wiring
work. No genuine same-repo family exists in neural-lace itself (checked).
**Action:** in the pt-marketing repo, add a header line `parent-plan:
2026-04-20-a2p-10dlc-multi-channel-consent` to
`docs/plans/2026-04-23-a2p-campaign-resubmission.md`, in the header block
(after `Status:`/`Execution Mode:`, before the first blank line/`##`
heading) — same-project (same-repo) resolution only applies within ONE
repo, so this retrofit is cosmetic/documentary until cross-repo resolution
is itself in scope (decide-and-go (b) in the plan's Decisions Log defers
that).
**Filed by:** cockpit-roadmap-redesign R11 retrofit research (this build).

## ESTATE-T1-HB-CLASSIFY-PERF-01 — hb_classify's transcript-mtime join is slow under real machine scale/contention

**Severity:** P2 (correctness unaffected; wall-clock only).
**Finding (PROVEN at build time, accountable-estate-program-2026-07 T1 build):**
`estate-janitor.sh run` against this machine's REAL state (17 real heartbeat
files, 547 real transcript files under `~/.claude/projects`, ~70-100
concurrent bash/claude/conhost processes at measurement time) took 96s to
classify just 17 heartbeats via `session-heartbeat-lib.sh`'s shared
`hb_classify` — the full run (heartbeats + process counts + `git worktree
list` across 94 real worktrees + branch enumeration + signal-ledger tail +
ask-registry fold) did not complete within 600s. Isolated timing: heartbeats
09:46:24->09:48:00 (96s for 17 files); process_counts 09:48:01->09:48:03 (2s,
expected — one wmic call); worktrees started 09:48:06, still running at the
120s debug-script deadline.
**Hypothesis, tested and REFUTED:** suspected `hb_is_stale`'s transcript-
mtime join (`_hb_find_transcript`'s `find -maxdepth 4` over the full
`~/.claude/projects` tree, 547 real files) as the dominant cost. Refutation
test run: `OBS_TRANSCRIPTS_ROOT=<empty-dir> estate-janitor.sh run` (bypasses
every transcript find entirely) still did not complete within 90s, same as
the un-bypassed run — REFUTES the transcript-join-alone hypothesis. The real
bottleneck is broader: most likely the `git worktree list --porcelain` +
per-repo `for-each-ref` branch enumeration across this machine's 94 real
worktrees (each orphan-branch row still does a `_ej_json_escape` pair of
forks), compounded by this machine's ~70-100 concurrent bash/claude/conhost
processes at measurement time making EVERY fork in the pipeline
(heartbeats' hb_classify, worktree/branch enumeration, jq calls) slower than
on an unloaded machine — not one single hot spot but broad fork-cost
inflation under real contention. Not further isolated (see Action below —
next attempt should instrument `_ej_collect_worktrees_and_orphans`
specifically, the way heartbeats was isolated here, before assuming which
sub-path to optimize next).
**Not fixed in T1** — `hb_classify` is a shared, already-self-tested oracle
(session-heartbeat-lib.sh) used by session-heartbeat.sh's own sweep and
harness-doctor.sh; patching its internals is out of T1's scope (Chesterton's
Fence + risk of regressing a load-bearing shared classifier) and arguably
belongs to this SAME program's later admission-governor slices (T3+), which
exist precisely to address machine-load-driven cost. estate-janitor.sh's own
--self-test (13/13, fixture-sandboxed, fast) proves the REDUCER's logic is
correct; this finding is about wall-clock on ground truth this machine
happens to carry right now, not a defect in the T1 reducer.
**Action (future):** either (a) profile hb_classify directly to confirm/
refute the transcript-find hypothesis and consider indexing `~/.claude/
projects` once per janitor tick instead of once per stale session, or (b)
accept the cost and size the scheduled task's cadence/ExecutionTimeLimit
accordingly (install-estate-janitor-task.ps1 currently ships a 10-minute
limit at a 5-minute default cadence — MAY need widening on this specific
machine until (a) lands).
**Filed by:** accountable-estate-program-2026-07 T1 build (estate-janitor.sh
+ estate-brief.sh).

## CONTEXT-WATERMARK-WINDOW-TABLE-STALENESS-01 — the model→window allowlist goes stale by default on every model launch

**Severity:** P2 (honesty machinery works; the number is still wrong until a human notices).
**Finding (PROVEN, 2026-07-28):** `hooks/context-watermark.sh` resolves its
denominator from a HARDCODED model→window allowlist (`_model_window`). Any model
not in the table falls through to a conservative 200,000 default. On this
session (model `claude-opus-5`, real window 1,000,000) the hook reported
"~74% of 200000" and then "~90% of 200000" while the client's own readout showed
163.2k / 1.0M = **16%** — a 5x overstatement that pushed the session toward
premature checkpointing.

**Why this is a class, not an instance:** this is the SECOND occurrence of the
identical failure. The 2026-07-20 incident
(`docs/lessons/2026-07-20-context-watermark-window-and-context-pressure.md`)
was the same bug on `claude-opus-4-8`. That fix added the ASSUMED label and the
model family to the table — making staleness HONEST but not RARE. The table
necessarily goes stale every time a model ships, the failure is silent, and the
detection mechanism is "an operator eventually notices the percentage is
absurd." Adding one family per incident is symptom treatment; expect a third
occurrence on the next model launch.

**Fix directions (evaluated 2026-07-29 — see RESOLUTION below):**
(a) invert the default — treat an unknown model as UNKNOWN and suppress the
    percentage entirely rather than printing a confidently-wrong one against an
    assumed denominator (the message already carries a "never a stop reason"
    clause, so suppression costs little);
(b) read the window from the session's own usage payload if the client exposes
    it, making the table a fallback rather than the authority;
(c) keep the table but add a doctor check that fails when the CURRENT session's
    model is absent from it — turning silent staleness into a visible RED.

**Immediate mitigation applied 2026-07-28:** `claude-opus-5*` added to the 1M
branch + regression scenario T17b; self-test 21/0. This closes the instance,
NOT the class.

**RESOLUTION 2026-07-29 — option (a), with the detector rebuilt in band.**
Plan: `docs/plans/context-watermark-window-class-fix.md`.

*(b) RULED OUT with evidence, not assumed.* The real window is NOT reachable from
a PostToolUse hook on client 2.1.219:
- the client's own hook-payload schema is `{session_id, transcript_path, cwd,
  prompt_id?, permission_mode?, agent_id?, agent_type?, effort?}` + `{hook_event_name,
  tool_name, tool_input, tool_response, tool_use_id, duration_ms?}` — no model, no
  window;
- `message.usage` in the transcript carries a numerator only (`input_tokens`,
  `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`,
  `cache_creation`, `server_tool_use`, `service_tier`, `inference_geo`, `iterations`,
  `speed`). A grep for `context_window` / `contextWindow` / `max_input_tokens` /
  `window_size` / `context_limit` across all 67 real transcripts on this machine
  returned ZERO hits;
- no env var exposes it — `CLAUDE_CODE_MAX_CONTEXT_TOKENS` is an operator-set INPUT
  that the client itself honors only under `DISABLE_COMPACT` or for non-`claude-`
  model ids, so trusting it as the denominator would re-create confidently-wrong;
- no client-written file exposes it — `~/.claude.json`'s `autoCompactWindowsCache`
  is consulted for `claude-sonnet-4-6` only and is null here; `~/.claude/debug/*.txt`
  does print `autocompact: … effectiveWindow=N` but those files carry no reference to
  the session id a hook receives and depend on debug logging being on.
- THE ONE CHANNEL THAT DOES EXPOSE IT: the StatusLine command input carries
  `context_window.context_window_size`. This harness configures no `statusLine`, and
  the desktop entrypoint has never been observed to run one here — wiring it would be
  claiming a mechanism that has not been seen to fire (constitution §10). **If a status
  line is ever adopted, that is the path that retires the table entirely** — the
  status-line script persists `context_window_size` keyed by session id and the hook
  reads it as the authority. Operator call, not a builder call.

*(c) NOT CHOSEN.* Viable — the running session's model IS readable from the newest
transcript — but strictly weaker: the wrong percentage is still emitted, and it is
only caught whenever someone next runs the doctor.

*(a) SHIPPED.* An unknown model now yields NO denominator, so no percentage can be
printed at all — the harm is structurally impossible, not merely less likely. Because
suppression alone would have destroyed the only existing detector (the absurd
percentage), the detector is rebuilt IN BAND: one non-numeric maintenance notice per
session naming the model, `_model_window`, both candidate readings as an explicit
either/or, and the `CONTEXT_WATERMARK_WINDOW` escape hatch. Self-test 21/0 -> 28/0 on
BOTH `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15, every new control
mutation-verified, and demonstrated on this machine's real 8 MB session transcript
(pre-fix: "~463% of 200000 … AT THE 85% MARK"; post-fix: the UNKNOWN notice).

**Residual risk (honest):** on an unlisted model the watermark goes DARK — no 70%/85%
nag and no proactive `session-snapshot.sh` run for that session. The PreCompact backstop
(`pre-compact-continuity.sh`) still covers overflow, and the notice tells the reader how
to restore the watermark in one edit or one env var, but this is a real trade: a missed
early nag in exchange for an impossible false alarm. Also unchanged: keeping
`_model_window` current is still manual — option (a) makes staleness loud and harmless,
it does not make it self-healing. Only the StatusLine path above would do that.

**Filed by:** neural-lace session, 2026-07-28 (operator-reported: "Context is not at 74%").
**Class fix by:** builder session, 2026-07-29.

---

## macOS portability M3 — residuals left alone (deliberate, with reasons)

**Filed by:** plan-phase-builder, task M3 of `docs/plans/macos-portability-2026-07.md`, 2026-07-29.
Context: all 11 real `timeout` callsites now route through `nl_run_bounded`
(`adapters/claude-code/hooks/lib/portable-timeout.sh`). These three things were
noticed during that work and deliberately NOT fixed in M3's scope.

1. **`hooks/lib/*.sh` self-tests are invisible to the doctor's sweep.**
   `check_selftest_sweep` globs `"$hooks_dir"/*.sh`, which does not descend into
   `hooks/lib/`. `portable-timeout.sh` ships a 21-assertion `--self-test` that
   therefore never runs in `harness-doctor --full`, and neither do any other
   lib self-tests. This is squarely M5's remit (make portability a mechanism);
   the sweep runner M5 builds should include `hooks/lib/*.sh`.

2. **The GNU `timeout` fast path still has no `-k` escalation.** `nl_run_bounded`'s
   fallback TERMs then KILLs the process tree; the GNU path sends only SIGTERM,
   because adding `-k` would change behavior on the Windows machines and the plan
   puts that out of scope. Consequence: on a GNU box a child that ignores SIGTERM
   still survives its bound. Worth revisiting as its own change, with the Windows
   machines in the test matrix.

3. **`propagation-trigger-router.sh` fails 9/14 self-test scenarios on macOS for a
   reason unrelated to `timeout`.** Measured on both bash 3.2.57 and 5.3.15, with
   GNU `timeout` present. The failures come from the scenarios' temp-dir fixture:
   `.../propagation-S10.XXXX.AId1qw7HeJ/build-doctrine/telemetry/propagation.jsonl:
   No such file or directory` (router line 648) — a BSD-vs-GNU `mktemp` template
   difference, not a bound. Pre-existing before M3 and unchanged by it. Belongs to
   the M2/M4 portability sweep or its own entry.

### Two defects hit while landing M3 (found by using the harness, not by reading it)

4. **`scope-enforcement-gate.sh` is not bash-3.2 compatible — it breaks on stock macOS.**
   PROVEN: `printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m t"}}' |
   /bin/bash adapters/claude-code/hooks/scope-enforcement-gate.sh` on bash 3.2.57 prints
   `line 1957: declare: -A: invalid option` then `line 1980: ...: division by 0` and exits 0 —
   i.e. the gate FAILS OPEN and enforces nothing. Under Homebrew bash 5.3.15 the same input
   blocks correctly. On a stock Mac `bash` IS 3.2.57, so this blocking gate silently stops
   blocking. Same class as M3/M4 but a language-feature issue (`declare -A`), not a GNU-tool
   issue, so it is outside M3's `timeout` remit. Worth its own task in this plan.

5. **The gate's path extractor silently drops a plain path when the same bullet has any
   backticked prose.** PROVEN: an `## In-flight scope updates` bullet reading
   ``- 2026-07-29: adapters/.../propagation-trigger-router.sh — bare callsite in `_self_invoke` ``
   left that file rejected as out-of-scope; backticking the PATH as well made it pass, with no
   other change. `extract_backtick_paths` loops all backtick pairs (scope-enforcement-gate.sh:1761-1771)
   and the plain path is never considered. The behavior is documented ("supports backticked
   paths") but the failure is silent and reads as "the gate ignored my scope update".
   Cheap fix: when no backticked token resolves to a real path, fall back to scanning the
   bullet for a plain path.

---

## ENSURE-COCKPIT-DARWIN-2026-07-29 — two pre-existing gaps found while adding the macOS LaunchAgent path

**Context:** building the macOS auto-start for `scripts/ensure-cockpit.sh`
(docs/decisions/065-macos-cockpit-launchagent.md). Both items below pre-date this
change and were found by using the harness, not by reading it — filed rather than
fixed beyond the one item that blocked this task's own deliverable (the exec bit,
fixed in the same commit since without it neither platform's code ever fires).

1. **`scripts/ensure-cockpit.sh` was tracked as git mode `100644` (non-executable)
   since its original introduction.** `session-start-digest.sh`'s splice invokes it
   by DIRECT exec (`"$HOOKS_DIR/../scripts/ensure-cockpit.sh"`, not
   `bash .../ensure-cockpit.sh`), so on any checkout that respects POSIX exec bits
   this silently made the ENTIRE mechanism — Windows path included, not just the
   new Darwin one — inert. Same defect class as the 2026-07-14 incident's I3
   (`needs-you.sh`, `session-resumer.sh`; docs/reviews/2026-07-14-mac-setup-
   incident.md). **Fixed in the ensure-cockpit darwin-support commit**
   (`chmod +x` + `git add`), since it directly blocked this task's own
   deliverable. Worth a repo-wide sweep: `git ls-files -s | grep '^100644.*\.sh$'`
   cross-referenced against every direct-exec (non-`bash `-prefixed) hook callsite,
   to find any OTHER scripts with the same latent gap.

2. **Four Windows self-test scenarios in `ensure-cockpit.sh` (`S4`, `S6`, `S10a`,
   `S10b`) fail on a stock Mac with no `powershell`/`powershell.exe` on PATH.**
   PROVEN: confirmed on the pre-Darwin script (commit 417c434), unrelated to this
   session's changes — `--self-test` reports `17 passed, 6 failed` on that
   unmodified file on this machine (S5 also touches the same resolution but
   happens to pass because it explicitly forces the "not found" branch it's
   testing). Each of the four asserts on the HARNESS_SELFTEST stub's SHAPE, which
   is only reached after `_ec_resolve_powershell` succeeds — and on a Mac with no
   real `powershell` install, that resolution fails first, so the scenario never
   reaches the code path it means to test. Cheap fix: add
   `ENSURE_COCKPIT_PS_OVERRIDE` to those four scenarios' env (exactly the fixture
   fix already applied to the NEW `D5` Windows-regression scenario in the same
   commit), making the suite fully portable to a Mac dev machine instead of only
   fully green on an actual Windows/MSYS host or one with a `powershell` shim
   installed.

3. **New bash-3.2 portability gotcha, not yet documented anywhere in the repo:
   `local a="$1" b="$a"` (a compound `local` where a LATER name references an
   EARLIER one declared in the SAME statement) is `unbound variable` under
   `set -u`.** PROVEN empirically on this machine (`/bin/bash` 3.2.57):
   ```
   f() { local a="$1" b="$a"; echo "$b"; }; set -u; f x
   # bash: line N: a: unbound variable
   ```
   Splitting into two separate `local` statements (`local a="$1"; local b="$a"`)
   fixes it. Caught while writing this task's self-test fixtures (a
   `_fake_launchctl` helper crashed this exact way and, worse, the crash left
   `ENSURE_COCKPIT_LAUNCHCTL_OVERRIDE` empty, which fell through to the REAL
   `launchctl` and bootstrapped a real — if harmlessly labeled — LaunchAgent on
   this machine; cleaned up by hand, see docs/decisions/065's Evidence section).
   Worth adding to whatever doc enumerates the bash-3.2 portability floor
   (`hooks/lib/portable-timeout.sh`'s header currently lists `declare -A`,
   `${x^^}`, `&>>`, `date -d` — this compound-`local` self-reference belongs
   next to those).

---

## ROADMAP-NARROW-VIEWPORT-COLLAPSE-01 — .roadmap-section collapses to ~2px tall under the .rm-layout column breakpoint

**Severity:** P1 (functional: the entire Roadmap tree becomes invisible, not just mislaid)
**What:** Live-verified (Round 12 build, 2026-07-29) via the running cockpit at :7733 in the
Browser pane at viewport widths ≤ ~1100px (the `@media (max-width: 1100px) { .rm-layout {
flex-direction: column } }` breakpoint, app.css:1560): `#roadmapSection`'s computed height
collapses to 2px (`getBoundingClientRect().height === 2`), clipping the entire tree — every row
still exists in the DOM (confirmed via the accessibility tree and `getComputedStyle` on
`#roadmapBody`, which reports its real, correct height) but is invisible, because `.pane`
(app.css:754) sets `overflow: hidden` with no explicit height.
**PROVEN pre-existing, NOT introduced by this session's work:** reproduced identically against
the UNMODIFIED pre-Round-12 `app.css`/`roadmap.js` (restored via `git show HEAD:...` and
temporarily swapped into the live server's checkout, then reverted) — same 2px collapse, same
viewport threshold. Out of this session's scope (the ux-ia-auditor's 9 build items say nothing
about this) and NOT fixed here per scope discipline.
**Suspected mechanism (HYPOTHESIZED, not yet fixed/verified):** `.rm-layout > .roadmap-section {
flex: 1 1 0; min-width: 0; }` (written for the DESKTOP row-direction layout, where `flex: 1 1 0`
governs WIDTH) is unconditionally reused when the media query flips `.rm-layout` to
`flex-direction: column` — at that point `flex: 1 1 0` governs HEIGHT instead, and per the
flexbox spec an item with non-`visible` overflow gets an automatic minimum main-size of 0; with
no sibling/ancestor supplying extra height for `flex-grow` to distribute, the item collapses
toward its flex-basis (0) instead of its content's natural height. `roadmapBody`'s own reported
height (563, at the same time `roadmapSection`'s height read 2) is the smoking gun: the child's
box is fully computed but the parent's box does not enclose it.
**Refutation criterion:** set `.rm-layout.column-mode > .roadmap-section` (or an equivalent
column-specific override) to `flex: 1 1 auto` (or add `min-height: 0` is NOT the fix — that
would make it worse; the fix direction is `flex-basis: auto` for the column case) and re-measure
`#roadmapSection`'s height at 800px width; if it now matches content height, the hypothesis is
CONFIRMED — if it still collapses, a different mechanism is at play and this diagnosis is
REFUTED.
**Fix:** scope a column-mode override inside the existing `@media (max-width: 1100px)` block
(app.css:1560-1563) — e.g. `.rm-layout { flex-direction: column; } .roadmap-section { flex: 1 1
auto; } .rm-sidebar { flex: none; max-width: none; width: 100%; }` — then re-verify against a
real narrow viewport (not just the desktop 1600px width this session verified Round 12's actual
changes at, to sidestep this exact bug).
**Filed by:** neural-lace Round 12 session, 2026-07-29 (discovered during live verification of
the ux-ia-auditor cockpit-roadmap-redesign build; not part of that dispatch's 9 items).

## SELF-SYNC-GUARD-INSTALLSH-RETROFIT-01 — install.sh still carries its own inline copy of the self-sync primitives

**Severity:** P3 (no functional gap; pure drift-prevention follow-up).
**Context:** `install.sh` (4e29dc6, 2026-07-29) and `session-start-auto-install.sh`
(same day, follow-on urgent fix) both need SELF-SYNC-01 protection (a sync/prune/merge
whose target resolves, through a symlinked live path, onto its own source). The shared
detection primitives (`resolve_real_path`, `_sync_self_check`, `_resolves_into_dir`) now
live in `adapters/claude-code/hooks/lib/self-sync-guard.sh`, sourced by
`session-start-auto-install.sh`. `install.sh` still carries its OWN inline copy of the
same three functions (from 4e29dc6), not yet switched to source the shared lib.

**Why not done together:** see `docs/decisions/065-self-sync-guard-signal-level.md`
("Related, NOT done here"). `install.sh`'s inline copy was hours-old, proven (12/12 on
both bash interpreters), and this session was expressly forbidden from running
`install.sh` itself — the least risky path was to leave it alone and extract the shared
lib fresh for the new consumer, rather than refactor an already-verified emergency fix
without the ability to smoke-test the refactor end-to-end.

**Fix:** replace `install.sh`'s inline `resolve_real_path()` / `_sync_self_check()` /
`_resolves_into_adapter_dir()` (install.sh:290-410ish) with a `source
"$ADAPTER_DIR/hooks/lib/self-sync-guard.sh"` (keeping `_resolves_into_adapter_dir()` as a
one-line wrapper around the shared `_resolves_into_dir "$1" "$ADAPTER_DIR"`, so its
existing call sites need no changes) and re-run
`tests/install-self-sync-guard-test.sh` (12/12 on both interpreters) to confirm no
regression — that test extracts real function bodies at run time, so a lib-sourcing
refactor needs its `FUNCS` extraction taught to also source the lib file, or the test's
`resolve_real_path` calls will find nothing defined.
**Filed by:** neural-lace session, 2026-07-29 (session-start-auto-install.sh SELF-SYNC-01 fix).


## ASK-SENTINEL-PER-SITE-REGRESSION-TESTS-01 — IMPLEMENTED 2026-07-29 (site-local regression tests added at all 4 remaining extractors; dual inventory collapsed)

**Severity:** P3 (all six sites PROVEN correct today by the delta re-review's isolation tests; this is future-regression hardening).
**Context:** the `'<'* | none` ask-id sentinel guard (commit 0758232, review
record hcr-20260729-4586088a) lives at 5 extractors + the writer, but only
remap (Scenario F) and progress-log-lib (Scenario 1i) carry site-local
none→empty regression assertions. plan-lifecycle.sh, workstreams-emit.sh,
merge-scan-lib.sh (incl. its git-fallback branch), and close-plan.sh got
guard-only edits — a future site-local miss would not fail that site's own
suite. Second advisory from the same review: the guarded-sites inventory is
hand-maintained in TWO comments (plan-template.md SENTINEL COUPLING +
progress-log-lib.sh _pl_is_none_sentinel) — currently consistent, drift is
silent; prefer one canonical list + reference, or a doctor grep check.
**Action:** add a none-header→empty (and real→preserved) assertion to each of
the four uncovered suites; collapse the dual inventory to one canonical list.
**Resolution (2026-07-29):** added a site-local none-header→empty assertion
to each of the four uncovered suites, exercising that site's OWN extractor
(real-id→preserved already existed at all four via pre-existing scenarios,
cited inline): plan-lifecycle.sh Scenario 13c (`extract_ask_id`; real-id
already covered by Scenario 14), workstreams-emit.sh PL4e
(`_resolve_ask_id_for_plan_slug`; real-id already covered by PL1),
merge-scan-lib.sh Scenarios 21-23 (`_ms_resolve_ask_id` — added BOTH the
file-lookup arm, Scenario 21, and the previously-untested git-fallback arm
at ~line 340, Scenarios 22-23, covering both none→empty and real-id→
preserved since neither existed there before), close-plan.sh S22
(`extract_ask_id_cp`; real-id already covered by S20/S21). Collapsed the
dual-maintained inventory: progress-log-lib.sh's `_pl_is_none_sentinel`
comment now points to plan-template.md's SENTINEL COUPLING comment as the
single canonical list instead of hand-duplicating it. All touched suites
green (plan-lifecycle, close-plan, merge-scan-lib, remap, progress-log-lib).
(Sibling row ASK-SENTINEL-QUARANTINE-SURFACER-01 RESOLVED 2026-07-30 and
removed: quarantine/unlinked growth now surfaced via estate-janitor.sh's
`ask_sentinel` reduction + WARN-on-growth in estate-brief.sh, both suites
extended.)
**Filed by:** emitter-fix delta re-review PASS (2026-07-29, Minor advisories 1+2).


## ESTATE-T6-ADM-RATE-CAP-BYPASS-UNCLOSED-01 — ADM_ABSURD_RATE_PER_MIN left open (sibling of the closed session-cap bypass)

**Severity:** P3 (cosmetic inconsistency; zero production callsites today, same as the three
closed bypasses).
**Finding:** T6-PREREQUISITES (b) (accountable-estate-program-2026-07 T6, desktop build,
2026-07-29) closed three of the four T6-named env bypasses in
`adapters/claude-code/hooks/lib/admission-lib.sh` (`ADM_ABSURD_SESSION_CAP`,
`ADM_ESTATE_SNAPSHOT`, `ADM_STATE_DIR` — see `docs/decisions/065-admission-lib-env-bypass-closure.md`)
by gating them behind `HARNESS_SELFTEST=1`. `ADM_ABSURD_RATE_PER_MIN` (`_adm_decide`'s rate-backstop
threshold, same code shape as the now-closed `ADM_ABSURD_SESSION_CAP`) was NOT one of the four
bypasses the 2026-07-28 review named, so it was deliberately left out of that slice's scope — but
it is the identical failure class (an unauthenticated environment override of an absurd-level
backstop) sitting right next to the closed one, and a reviewer comparing the two will find the
asymmetry confusing.
**Not fixed here** — out of the T6-PREREQUISITES (b) task's explicitly-scoped four bypasses;
closing a fifth, un-named item risked scope creep in a slice whose acceptance criterion counts
exactly four.
**Action (future):** apply the same `_adm_session_cap`-style closure to the rate backstop (a
`_adm_rate_cap()` resolver honoring `ADM_ABSURD_RATE_PER_MIN` only under `HARNESS_SELFTEST=1`),
with a matching self-test scenario pair (closed in production / still available under
HARNESS_SELFTEST=1), for consistency — low effort, same pattern already proven in this build.
**Filed by:** accountable-estate-program-2026-07 T6-PREREQUISITES (b) build (desktop, 2026-07-29).
## NL-ISSUE-JSON-FIELD-BSD-SED-ALTERNATION-BUG-01 — FIXED: `_nli_json_field`'s `\|` alternation silently matched nothing under BSD sed

**Severity:** was `error` (silent, total breakage of a load-bearing helper on
every macOS machine); **RESOLVED** in the problems-persist build, commit
in this PR.
**Context:** discovered while adding new self-test scenarios to
`adapters/claude-code/scripts/nl-issue.sh` for the problems-persist
mechanism's `source` field (`docs/decisions/065-problems-persist-warn-
consolidation.md`). `_nli_json_field`'s extraction regex used BRE `\|` for
alternation (`\(\([^\"\\]\|\\.\)*\)`) — a GNU sed extension. BSD sed (macOS
default `/usr/bin/sed`, confirmed this is what every Bash invocation on this
machine resolves to) does not support `\|` in basic-regex mode and silently
matches nothing (no error, empty capture group) rather than failing loud.
Confirmed PRE-EXISTING and NOT introduced by this build: `git show
HEAD:adapters/claude-code/scripts/nl-issue.sh --self-test` (pristine)
already gave 13 passed / 11 failed on this machine — Scenario 1 (--list
round-trip), Scenario 2 (24h dedup: 3 identical appends produced 3 lines
instead of folding to 1 with count:3), and Scenarios 9-10 (escalation
fixtures) were ALL failing for this ONE root cause, not four separate bugs.
**Fix:** switched `_nli_json_field` to `sed -nE` (extended regex, where bare
`|` alternation is supported identically by BSD sed 2.6.0-FreeBSD and GNU
sed 4.10 — verified against both via `gsed`) — a portable fix, not a
platform-specific workaround. Full self-test suite (now 32 scenarios) is
32/0 PASS under both `/opt/homebrew/bin/bash` (5.3) and `/bin/bash` (3.2.57)
post-fix; RED-GREEN proven by reverting the one line back to the `\|` form
(13 failures reproduce exactly) then restoring the `-E` fix (32/0 again).
**Filed by:** plan-phase-builder, problems-persist build, 2026-07-29.

## WORKSTREAMS-READ-R20-CURSOR-MTIME-FLAKE-01 — self-test Scenario R20 fails intermittently, pre-existing, unrelated to the problems-persist build

**Severity:** P3 (self-test signal only).
**Context:** discovered while adding the PROBLEM-CAPTURE splice to
`adapters/claude-code/hooks/workstreams-read.sh` (problems-persist part 3).
Confirmed PRE-EXISTING via an in-place `git stash` A/B (same machine, same
directory, only this one file reverted): the UNMODIFIED file also gives
57 passed / 1 failed, same R20 assertion ("cursor mtime advanced") failing.
Likely an mtime-resolution race (two cursor writes within the same
filesystem timestamp granularity), not something this build touched.
**Action:** replace the mtime-inequality check with a content/event-id
comparison, or add a forced sleep/nanosecond-mtime read.
**Fold-in point:** any slice touching workstreams-read.sh's cursor-fast-path
logic next.
**Filed by:** plan-phase-builder, problems-persist build, 2026-07-29.


## ESTATE-T4-PRE-EXISTING-UNREGISTERED-WORKTREES-01 — 25-27 real worktrees predate the no-orphan mechanism; named, not silently pruned or hidden

**Severity:** P3 (informational debt; the mechanism itself is forward-looking by design).
**Context:** accountable-estate T4 shipped no-orphan registration (spawn-worktree.sh
writes an open registration on `--apply` create; close-worktree.sh/`--remove` closes
it) plus `scripts/estate-attribution-check.sh`, the tool deriving T4's own outcome
metric: "zero unattributable worktrees/branches older than 48h." Run live against
this machine's real estate at build time (2026-07-29):
```
bash adapters/claude-code/scripts/estate-attribution-check.sh --repo /Users/misha/Claude/neural-lace
```
result: **zero** unattributable worktrees older than 48h — but PROVEN this is an
artifact of freshness, not attribution: `git worktree list` on this repo showed 26
secondary worktrees (up from the "18 vs a budget of 6" ground truth cited at the
start of this build — active parallel building continued the whole session), and
every single one's last commit is under 12 hours old (checked directly: `git log -1
--format='%ci (%cr)'` on five sampled branches returned "4-6 hours ago"). None of
them carry a registration (the mechanism did not exist when they were created), so
as each ages past 48h it WILL start appearing in `estate-attribution-check.sh`'s
output with no registration to explain it — that is expected, honest pre-existing
debt, not a regression in the new mechanism. Cross-checked against a DIFFERENT,
liveness-based tool with no age gate — `worktree-hygiene-sweep.sh --stranded`, run
the same session — which reported 25 "no live owner" worktrees (up from the "7+"
figure in the same ground truth), all "last commit 0d ago": that tool answers "is
anyone actively working on this right now," a different question from T4's
"do we have an attribution record," and its higher, age-gate-free count is not a
discrepancy to reconcile — the two tools are deliberately asking different things
(see estate-attribution-check.sh's own header for the full distinction).
**Action:** none required by T4 itself — the mechanism is forward-looking per its
own outcome metric's re-check date below. When re-checking, any UNATTRIBUTABLE row
whose worktree was created BEFORE the T4 landing commit is this pre-existing debt
(triage manually via `worktree-hygiene-sweep.sh --stranded` + salvage-or-prune, same
as before T4 existed); any row for a worktree created AFTER that commit is a REAL
regression in the no-orphan mechanism and must be investigated as a defect, not
filed here.
**Re-check date (program rule 2):** 2026-08-01 (72h out — long enough for today's
sub-12h-old worktrees to cross the 48h threshold one way or the other, and for at
least one worktree created AFTER T4 landed to also cross it, which is the first
point this metric can demonstrate holding at zero for genuinely-covered work
rather than reading zero merely because nothing was old enough yet to test).
Re-run: `bash adapters/claude-code/scripts/estate-attribution-check.sh --repo
/Users/misha/Claude/neural-lace`; recurrence of a POST-T4-created unattributable
worktree auto-reopens this row per program rule 2.
**Filed by:** plan-phase-builder, accountable-estate T4 build, 2026-07-29.

---

## COORD-SYNC-NO-PEER-EXPORTS-YET-01 — the shared coord repo has zero `plan-export/*.json` files from any real machine

**Severity:** P2 (blocks the operator-facing outcome — "the cockpit shows other machines'
work" — even after this machine's own coord-sync loop is fully wired and running).
**Context:** built while wiring macOS coord-sync (`docs/decisions/066-macos-coord-sync-
launchagent-and-credential-fix.md`). Inspected the real `mishanovini/workstreams-
coordination` repo's tree: it has the OLD `tree-state/Office_PC.json` (the superseded
per-machine-tree-state architecture, cockpit-v2-push-materialized-store's predecessor) but
**no `plan-export/` directory at all** — meaning no real machine, including the operator's
own Windows boxes (Office_PC/BOOK), has run the CURRENT `coord-sync.sh` + `export-state.js`
cadence and published a `plan-export/<hostname>.json` yet. `server/peer-view.js` reads
ONLY `plan-export/*.json` (excluding self-hostname) — so even once this Mac's export lands
there, the cockpit's Peers section will show "no peers yet" (has_data reflecting only this
machine, or possibly none once self is filtered) until at least one OTHER machine ALSO runs
the new cadence.
**Action:** get `NL-CoordSync` genuinely registered and firing on at least one Windows
machine via the ALREADY-DOCUMENTED, operator-applied command in
`docs/runbooks/coord-sync.md` (`powershell -File adapters\claude-code\scripts\
install-coord-sync-task.ps1 -RepoPath "<path>"`) — this is explicitly NOT an agent-run step
per that runbook's own "Registration" section. Once ONE other machine's `plan-export/
<hostname>.json` exists in the shared repo, this Mac's next `coord-pull` will surface it
immediately (no further code change needed — the mechanism is generic across N machines
per the runbook's own "N-machine is the shipped architecture" note).
**Filed by:** neural-lace session, 2026-07-29 (macOS coord-sync wiring build).

---

## INBOX-SESSION-ID-ABBREVIATED-01 — needs-you.sh ledger items can carry an 8-char abbreviated `session` field instead of the full session UUID

**Severity:** P3 (the quarantine "open source session" resume-command affordance would render
an unresumable `claude --resume <8-char-prefix>` command if this ever reaches that path today).
**Context:** found auditing INBOX-MULTILINE-ASK-TRUNCATED-AT-RENDER-01 (round 14, workstreams-ui
cockpit). The real production ledger item `NY-1785357818-7d3f` carries `"session":
"a3fcb6ea"` — an 8-char hex PREFIX of a real session UUID, not the full id `claude --resume`
normally expects. `inbox-routes.js`'s `open_source_session.resume_cmd` builds
`'claude --resume ' + item.session` verbatim — if a QUARANTINED item (the only place this
affordance renders today) ever carries a session id shaped like this, the copyable command
would be unresumable. The shaping happens UPSTREAM of workstreams-ui, in whichever
hook/dispatcher passes `--session <id>` to `needs-you.sh add` (needs-you.sh itself never
truncates — `--session` is a plain passthrough CLI arg) — out of workstreams-ui's own file
scope to fix or even locate without a cross-repo grep.
**Action:** `rg -n -- '--session' adapters/claude-code/hooks/ adapters/claude-code/scripts/`
to find the emitter using an abbreviated id, then either pass the FULL session id at the
call site or (if `claude --resume` genuinely supports prefix matching) confirm that and close
this as a non-issue.
**Filed by:** plan-phase-builder, cockpit-roadmap-redesign round-14 build, 2026-07-29.

## NL-ISSUES-TRIAGE-20260730 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 60 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 2d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## PROGRESS-LOG-ID-JSONL-UNACCOUNTED-01 — the ~1090-1140 legacy `_id.jsonl` events have no provenance trail

**Severity:** P2 (possible historical audit-trail data loss; no LIVE-data
risk today since the writer-side backstop already quarantines new
occurrences — this is about the OLD, pre-fix events only).
**Finding (PROVEN, `progress-log-placeholder-ask-id-fix` Task 4 real run,
2026-07-30):** `~/.claude/state/progress-logs/_id.jsonl` — the file this
plan's whole Goal section is chartered around (1090 events at plan-author
time, 1140 per commit 0758232's later count including 2 more affected
extractor sites) — does not exist on the real machine, and no completion
receipt (`_id.jsonl.migrated`) or timestamped backup
(`_id.jsonl.migrated-<ts>`) exists anywhere under `~/.claude/state/`,
Trash, or elsewhere searched. The decisive check: `remap-placeholder-
ask-events.sh` preserves a migrated record's `ask_id` field BYTE-FOR-BYTE
(so a real migration would leave the literal fingerprint `"ask_id":"<id"`
sitting in `unlinked.jsonl` or a real ask file) — grepped for across
every `*.jsonl` in the state dir; the ONLY hits are the 26 NEW records in
`unattributed.jsonl` (Task 2's live writer-backstop catching fresh
placeholder writes, not migrated legacy ones). No git commit, backlog
row, SCRATCHPAD.md, or NEEDS-YOU.md entry documents a real run against
this file. HYPOTHESIZED, unresolved: either an earlier session deleted
`_id.jsonl` directly (bypassing this script and its mandatory backup —
a salvage-before-reset process violation) or some other undiscovered
repair path moved the data in a form this fingerprint check cannot see.
**Action:** if this is genuinely unrecoverable, this is a closed loss —
document as such and remove Task 4 of `progress-log-placeholder-ask-id-fix`
from any future completion claim; if a backup exists somewhere not yet
searched (another machine, a manual export, Time Machine), locate and
re-run the migration against it. Either way, close the provenance
question explicitly rather than leaving Task 4 ambiguously "done."
**Fold-in point:** whoever closes `progress-log-placeholder-ask-id-fix`
(task-verifier / orchestrator) should treat this as a required read
before flipping or archiving; not a blocking gate on its own (no live
risk), but the honest-completion bar for that plan.
**Filed by:** plan-phase-builder, Task 4 real-run investigation, 2026-07-30.

## ESTATE-T7-LOE-BACKFILL-FULL-MINE-PENDING-01 — full 161-plan LOE mine not yet run to completion on this machine

**Severity:** P2 (tool correctness proven; only the full-corpus artifact is outstanding).
**Finding (PROVEN at build time, accountable-estate-program-2026-07 T7 build):**
`adapters/claude-code/scripts/loe-backfill.sh` (new, this build) mines
`docs/plans/archive/*.md` + companion evidence + git history into a
calibration table. Correctness is proven two ways: (1) a 12-scenario
`--self-test` on a synthetic sandboxed repo, all PASS; (2) a REAL-data
25-plan subset mine (alphabetically first 25 of 161 archived plans, real
repo, real git history) completed cleanly with zero errors and plausible
output (3 classes populated, 100% wall-clock coverage, honest 0% builder-
sessions coverage for that specific subset — independently spot-checked:
`cockpit-v2-push-materialized-store.md`, NOT in the 25-plan subset, mines
correctly with `builder_sessions: 3` when run standalone, confirming the
extraction logic itself is sound and the 0% was a real property of the
subset, not a bug).
The FULL 163-plan mine (`bash adapters/claude-code/scripts/loe-backfill.sh`,
no args, writes `docs/loe/loe-calibration.json`/`.md`) was attempted 3x in
this session as a background task and was killed by the environment each
time (no error output at time of kill — it was mid-run, not crashing) before
completing. Same root cause as ESTATE-T1-HB-CLASSIFY-PERF-01 above: this
machine's demonstrated fork-tax (~3.4s per `git log --follow` invocation,
161 invocations ≈ 9 min best-case, longer under real contention) combined
with this session's tool-level background-process ceiling (empirically
observed to kill long-running background bash calls after several minutes
regardless of `run_in_background`).
**Not fixed in T7** — out of scope for a single builder session's wall-clock
budget; the tool itself needs no further change, only more wall-clock (or a
lower-fork-tax machine per docs/runbooks/windows-machine-perf-setup.md) to
produce the committed artifact.
**Action (future):** run `bash adapters/claude-code/scripts/loe-backfill.sh`
to completion — either in a long-lived foreground session, on the other
(faster) machine, or via a scheduled task with a generous time limit (mirror
install-estate-janitor-task.ps1's pattern) — then commit the resulting
`docs/loe/loe-calibration.json`/`.md` (path moved out of docs/plans/ by the
fd48741 review remediation — the plan gate rejected the rendered table
there). Consider adding a `--resume`/`--limit N` flag if this repeats, so a
killed run doesn't restart from scratch (deferred despite 3 kills — the
artifact is needed ONCE and the next attempt runs on a faster machine or a
generous scheduled-task limit, either of which removes the need).
**Filed by:** accountable-estate-program-2026-07 T7 build (loe-backfill.sh
+ plan-reviewer.sh Check 18).

---

**RETRY-GUARD-STATE-LEAK-DCG-01** (2026-07-29)
**Severity:** P2 (a retired script's own self-test corrupts real repo state
on repeat runs; the script itself is scheduled for hard-delete, so the fix
is small, but the leak is real and currently un-contained outside my
hardened caller).
**Finding (PROVEN, macos-portability-2026-07 M6 S11-flake investigation):**
`adapters/claude-code/attic/decision-context-gate.sh --self-test` scenario
ST1 (lines ~924-933) invokes `bash "$SELF" <<<...` without isolating CWD or
`RETRY_GUARD_STATE_DIR`. Its Tier-1-block path calls
`retry_guard_block_or_exit` (`hooks/lib/stop-hook-retry-guard.sh`), which
persists a counter at `${RETRY_GUARD_STATE_DIR:-.claude/state}/stop-hook-
retries-decision-context-gate-st1.txt` — CWD-relative, i.e. the REAL repo's
own `.claude/state/`. PROVEN: after ~90 repeated self-test runs during this
investigation, that file held `271db2a4f357|db280f21df93572e34539e6ee36d96
fafb11b255|93`. Once the counter crosses `RETRY_GUARD_THRESHOLD` (3), ST1's
own "exit 2" assertion starts failing — the gate silently downgrades
(exits 0) instead of blocking, because it believes it has seen the same
failure 3+ times, independent of whether this is really the 1st or 93rd
run. Sibling scenario ST9 already isolates correctly (it `cd`s into a fresh
`$TMP/run9-state` before invoking the child); ST1 (and possibly ST2/ST5/
ST11/ST12/ST28, not yet audited) does not.
**Not fixed here** — out of my dispatched scope (macos-portability M6 owns
only `adapters/claude-code/scripts/selftest-sweep-exclusions.sh` and
`docs/portability-baseline.txt`). I hardened the CALLER instead: my S11
loop (in `selftest-sweep-exclusions.sh`) now injects a fresh
`RETRY_GUARD_STATE_DIR`/`HARNESS_SELFTEST_DIR` per child invocation as
defense-in-depth, so the sweep itself no longer writes into real repo
state or depends on prior-run history. But `decision-context-gate.sh`
invoked ANY OTHER way (directly, or by a future caller that doesn't
replicate my isolation) still leaks.
**Action (future):** apply ST9's isolation pattern to ST1 (and audit ST2/
ST5/ST11/ST12/ST28) in `attic/decision-context-gate.sh`. Verify with 5+
repeated `--self-test` runs from a stable CWD: ST1 must stay PASS every
time, and no file may appear under the repo's real
`.claude/state/stop-hook-retries-decision-context-gate-*`. Also spawned as
task_8d243391 ("Fix retry-guard state leak in attic/decision-context-
gate.sh").
**Filed by:** macos-portability-2026-07 M6 build (S11-flake root-cause
investigation).

## ROADMAP-MULTI-PROJECT-CONFIG-NOT-SET-01 — the Roadmap's own multi-repo scan has no per-machine config on this machine; Circuit's real plans never reach the Roadmap tree

**Severity:** P2 (the mechanism is built and selftest-proven; only a config file is missing —
R9-8's "scan the operator's configured projects" ask is real practice on this machine, just
never wired to this ONE feature)
**What:** Live-verified 2026-07-30 (cockpit-roadmap-redesign Round 15, while building
`docs/reviews/cockpit-ui-requirements-ledger.md`): `GET /api/roadmap` at :7733 returns items
from exactly ONE project (`neural-lace`) — curl'd this session, 26/26 live items carry
`"project":"neural-lace"`. `config/projects.json` (the file `ROADMAP_PROJECTS_CONFIG` defaults
to, `neural-lace/workstreams-ui/server/roadmap-routes.js:494`) does not exist on this machine
(confirmed via `ls`) — only the tracked `config/projects.example.json` placeholder. This is a
DIFFERENT config file from the one the Docs browser already uses successfully
(`config/projects.js`'s `loadProjects()`, which auto-discovers `Circuit` via its own sibling-repo
scan independent of any config file) — the Docs button already lists 836 Circuit files
correctly; the Roadmap tree simply never learned Circuit is a project worth scanning for
`docs/plans/`.
**Not fixed here** — Round 15's dispatched scope was five operator complaints + one coordinator
addition (running-state roll-up, colour, plan links, Docs-button crash, the requirements ledger,
build-order banding), none of which named this gap; it surfaced incidentally while live-verifying
Round 9's R9-8 row for the ledger.
**Fix:** copy `config/projects.example.json` to `config/projects.json` on this machine and add
an entry pointing at the Circuit repo root (same shape `config/projects.js` already resolves for
the Docs browser); OR, better, have `roadmap-routes.js`'s project loader reuse
`config/projects.js#loadProjects()` directly instead of maintaining a second, differently-
configured project map — the two config surfaces (Docs browser vs. Roadmap scan) currently
require the SAME real information (project name -> repo root) entered twice, which is exactly
the kind of drift this whole ledger effort exists to catch.
**Filed by:** cockpit-roadmap-redesign Round 15 build, 2026-07-30 (discovered live while
verifying R9-8 for `docs/reviews/cockpit-ui-requirements-ledger.md`).

## OBS-DERIVE-SELFTEST-ERREXIT-LEAK-01 — `observability-derive.sh --self-test` crashes at Scenario 6h (rc=2), never running Scenarios 6h(remainder)/7/8/9/10/11

**Severity:** P2 (self-test coverage gap, not a production bug — `nl status --json` / `nl costs
--json` both verified clean end-to-end on this machine; the crash only hides LATER self-test
scenarios from ever running, including some of od_costs/od_why's own coverage)
**What:** PROVEN pre-existing, NOT a regression from the bash-3.2 `declare -gA` repair (this
task, 2026-07-30): `/bin/bash adapters/claude-code/hooks/lib/observability-derive.sh
--self-test` and the `/opt/homebrew/bin/bash` equivalent both exit rc=2 immediately after
Scenario 6h's first `od_costs`/jq call, before printing that scenario's pass/fail line —
verified byte-for-byte IDENTICAL output (40 PASS / 9 FAIL, same crash point) between this
task's fixed file and the untouched pre-fix commit (1256721) via `git stash` + re-run. Root
cause (traced with `bash -x`): Scenario 6f (`## od_costs tolerates a CORRUPTED cache file`)
brackets its risky call with `set +e` / … / `set -e` to capture an rc without aborting — but
the self-test's own top-of-block only ever does `set +u` (never `set -e`), so errexit was OFF
the entire time before 6f. Scenario 6f's trailing `set -e` therefore turns errexit ON for the
first time and leaves it on for every scenario after it (6g, 6h, 7, 8a, until Scenario 8b's own
`set +e`/`set -e` pair repeats the same mistake). The very next unprotected non-zero-returning
simple statement — Scenario 6h's `jq '...' "$OBS_COSTS_CACHE"` when the cache file does not yet
exist (jq's real "no such file" exit code) — then trips errexit and the whole self-test process
exits immediately via its `trap 'rm -rf "$TMP"' EXIT`, silently skipping every scenario after it
(unrelated Scenarios 6h-tail/7/8a/9/10/11 never execute this run, INCLUDING their PASS/FAIL never
being counted — the printed "40 passed / 9 failed" undercounts what a healthy run would report).
The same pattern exists at the 2955-2958 (Scenario 6b) and 3280-3283 (Scenario 8b) `set +e`/
`set -e` pairs — 8b's trailing `set -e` re-triggers the same leak for whatever follows it.
**Not fixed here** — out of this task's scope (three `declare -gA` clusters + an `${arr[@]}`
empty-array sweep in the same file); fixing it means editing self-test scenario bodies unrelated
to that fix, which would mix an unrelated bug fix into this task's commit.
**Fix:** each `set +e` / `<command>` / `set -e` bracket should restore the AMBIENT state, not
force errexit on — replace the trailing `set -e` in these three blocks with `set +e` (a no-op,
since that's the self-test's actual resting state), or better, drop the `set +e`/`set -e` pair
entirely and just capture `rc=$?` directly (a bare command statement's non-zero exit does not
abort a script that never enabled `set -e` to begin with).
**Filed by:** bash-3.2 portability repair build (this task), 2026-07-30 — discovered while
running this lib's own `--self-test` under both interpreters to verify the `declare -gA` fix.
- **AGENTS-ROSTER-REEVALUATION-01** (high, operator 2026-07-30): "I'm also wondering if we need
  to improve the agents (the UX ones in particular). We rebuilt many of them a few weeks back and
  only enabled a few of them because Claude told me there was substantial risk in doing so. I'd
  like to reevaluate that with you at some point." → a joint sitting: inventory the rebuilt-but-
  disabled agent roster, restate the original risk assessment against today's harness (RI pipeline,
  verification-dispatch, worktree isolation now exist — the risk calculus has changed), and
  propose enable/improve/retire per agent. Owner: orchestrator prepares the brief; operator
  decides. Not started.
- **RUNNER-POST-WRITER-REFUSAL-REVERT-01** (minor, review 2026-07-30): review-runner.sh's
  defense-in-depth stray check (~line 359) fires AFTER the record writer ran; its "re-run
  finalize" remedy can then mint a committed index referencing an orphaned record. Fix: revert
  writer output (rm record, checkout index, unstage) on that refusal path, or name the cleanup
  in the remedy text. HYPOTHESIZED-frequency (microsecond window); detectable-after via
  review-index-consistency.
- **OBS-COMMENT-DRIFT-670-01** (minor, review 2026-07-30): observability-derive.sh lines
  670-673 header still describes the retired _OD_*_BY_SID assoc arrays; rewrite to name the
  string-index + fold-at-lookup shape (the STRUCTURE note beneath is already correct).
- **MANIFEST-LIB-HOOKS-RESOLUTION-01** (minor, review 2026-07-30): manifest.json
  git-command-parse entry has hooks:[] so manifest-check cannot path-resolve it (5 sibling lib
  entries carry "lib/..." refs). Add the hooks[] ref or note the unpoliced drift in
  honest_status; sweep other hooks[]-less entries via the review's jq query.

## CLOSE-PLAN-MECHANICAL-EVIDENCE-WHOLE-FILE-SCAN-01 — verify_task_mechanical's prose-evidence path is whole-file, not block-scoped

**Severity:** Minor (narrow false-accept surface, not a known live incident)
**What:** `close-plan.sh`'s `verify_task_mechanical` Path (b) — the prose-evidence-with-commit-SHA
fallback, `adapters/claude-code/scripts/close-plan.sh` around the `Task ID:`/`commit[[:space:]:]`
greps near line 480 — checks that the evidence file contains a `Task ID: <task_id>` line
SOMEWHERE and a `commit <sha>` citation SOMEWHERE, independently, rather than requiring both
inside the SAME task's block. A multi-task evidence file could satisfy task N's mechanical check
with task M's commit citation if task N's own block never got one. `verify_task_full` (the
`Verification: full` sibling) already solved the equivalent problem via its Task-ID-anchored
block-boundary parser (the 2026-07-30 T9 parser-bug fix); this Path (b) predates that fix and was
never retrofitted onto the same block-splitting discipline.
**Fix:** reuse `verify_task_full`'s awk block-boundary approach (anchor on `^[[:space:]]*Task ID:`
to open/close a block) for Path (b)'s commit-SHA check too, so both verification tiers parse
evidence files the same way.
**Filed by:** close-plan.sh / plan-recheck-sweep.sh harness-reviewer REFORMULATE remediation,
2026-07-30 (a pre-existing code comment at this callsite promised "see backlog" for this exact
limitation with no corresponding entry ever filed; this entry closes that promise). Also logged
via `nl-issue.sh` the same session for cross-project triage visibility.
- **ESTATE-MERGE-GUARD-COMMENT-MOVED-PHRASE-01** (minor, review 2026-07-30): the F4-softened
  static-guard comment still lists "or moved elsewhere" as caught; re-run MUT4 proves a moved
  call leaves the guard green. Drop the phrase or qualify "moved out of this file".
- **ESTATE-MERGE-ACK-SHA-VALIDATION-01** (minor, review 2026-07-30): --acknowledge's
  rev-parse isn't pinned to ^{commit} nor checked as a merge commit in the target's history
  (bounded by required --reason + audit row); acknowledged rows carry empty source_branch
  ("acknowledged:  -> target" cosmetic). Two one-line fixes for a future pass.
- **CLOSE-PLAN-VERIFIER-LINE-FAIL-VETO-01** (minor, closure re-review 2026-07-30): the M1
  verdict anchor accepts a `Verifier:` line reading "PASS conf 8, OVERALL FAIL" (shape exists
  at cockpit-roadmap-redesign-evidence-t3.md:51) — inherent in the reviewer's own recommended
  anchor; add a FAIL/INCOMPLETE veto token to the block parser.
- **PRS-DISABLE-SKIP-ENV-GATING-01** (advisory, closure re-review 2026-07-30): gate
  _PRS_SELFTEST_DISABLE_DEFAULT_SKIP on HARNESS_SELFTEST=1 per the S7c precedent (currently
  any exporter re-arms the default-date skip; only-more-aggressive + loud, so advisory).
- **COCKPIT-NEVER-REVIEWED-01** (HIGH, operator 2026-07-30, MEASURED): `jq -r '.entries[].path'
  docs/reviews/records/index.json | grep -c workstreams-ui` = **0** of 255 review records. The
  review-before-deploy surface (`rrg_in_surface`) matches only `adapters/claude-code/**`, so the
  cockpit UI — the surface the operator actually uses — has never been adversarially reviewed and
  no mechanism requires it. EVERY operator-reported UI defect this week (green-means-running,
  drag no-op, dead Inbox file:// links, empty Requests tab, raw stderr panels) lived in unreviewed
  code. Builder dispatched to extend the surface + propose the two sibling controls below.
- **SHAPE-ONLY-ASSERTIONS-FALSE-GREEN-01** (HIGH, operator 2026-07-30, PROVEN today): a
  behavioural claim asserted by a source-text regex can pass while the feature is broken live —
  cockpit.selftest.js R17-DRAG-2 matched `insertBefore(...)` and passed while the optimistic drag
  move was a live no-op. Fixed instance-wise by R17-DRAG-3 (real-execution + mutation-proven);
  the CLASS needs a mechanism (lint/doctor check flagging behavioural claims backed only by regex).
- **UI-ACCEPTANCE-SANDBOX-ONLY-01** (HIGH, operator 2026-07-30): UI builders verify against
  fixture servers (:7799); the operator finds the bugs at :7733 against real data. Round 16's blue
  sweep, the Inbox links, and the requests pipeline all passed in sandbox and were broken live.
  A UI round's acceptance must require evidence from the real deployed app.

## ROADMAP-FALSE-ETERNAL-RUNNING-01 — emitter fix WRITTEN + HAND-INSTALLED, still NOT MERGED (and therefore reversible at any SessionStart)

> **STATUS DISCIPLINE (corrected 2026-07-30 after an adversarial refutation caught this entry
> committing the very defect class it documents).** This entry previously headed
> "emitter fixed 2026-07-30" and described the change as "**FIX (landed 2026-07-30 …)**" while
> **nothing was committed and the live hook was byte-identical to the unfixed one.** Constitution
> §1: done = merged to master with a SHA. The correct status of the work described below is
> **WRITTEN, staged in a builder worktree, NOT merged and NOT installed.**
>
> **SUPERSEDED 2026-07-31 — the "NOT INSTALLED" half of the heading above was itself stale.**
> The shasum this entry used to carry at this point — `shasum ~/.claude/hooks/workstreams-emit.sh`
> == `git show HEAD:adapters/claude-code/hooks/workstreams-emit.sh | shasum` ==
> `87743bca9d440964b0a4f7ca01216eef232dd349`, cited as proof the live hook was the OLD one —
> was true when written and is no longer. The fix WAS hand-installed on the authoring machine
> at 2026-07-30 20:05 PDT, ~30 minutes AFTER commit `f018623`.
> *(Wording repaired 2026-08-01 during transport: this sentence read "the shasum **below**"
> while `ab8055b` had DELETED that shasum block in the same hunk, so the pointer resolved to
> nothing. The deleted value is restored inline above rather than left as a dangling
> reference — a retraction that cites evidence the reader cannot find is not a retraction.)*
>
> **PROVEN now:** `shasum -a 256 ~/.claude/hooks/workstreams-emit.sh` ==
> `git show f018623:adapters/claude-code/hooks/workstreams-emit.sh | shasum -a 256` ==
> `031fe941d6d7236a5a348dbb3b9426f6e0a93eaef7d2007b96a9ae8882d9e315` — byte-identical, so the
> live hook IS the fixed one. Master's blob differs
> (`94905d0d4faa49328ff8c919b40869b3ac2286d5b2e712666b1154eb2c3d2026`), which is exactly the
> risk below. (The live file is a hand-installed regular file, not a symlink.)
>
> **BOTH HASHES ABOVE ARE NOW STALE, AND THE PREDICTION BELOW CAME TRUE — measured
> 2026-08-01 on the TRANSPORT machine (Windows), by the commit that added this paragraph.**
> The two shasums above were taken on the AUTHORING machine (macOS) on 2026-07-31; neither is
> a fact about this repo today, and "this machine" in the paragraph above does not mean the
> machine you are reading it on. Re-executed here with `sha256sum`:
> - master's blob at `dc05aa2` = `8c75322213828e41efd223da96df01d9e29f2309483e253d463ebc4ed7790b7e`
>   — **not** `94905d0d…`. Master's copy moved on (the NL-ATTRIBUTION attribution pipeline,
>   scenario PL4e, the 120s debounce default), which is precisely why a bare blob hash goes
>   stale the moment EITHER side edits.
> - live `~/.claude/hooks/workstreams-emit.sh` on this machine = `8c753222…` — **byte-identical
>   to MASTER**, i.e. the content WITHOUT the defect-4 fix. Whether that is a revert by
>   `session-start-auto-install.sh` or simply a machine that never got the hand-install cannot
>   be told apart from a hash, and no claim is made either way. What IS proven: the fixed blob
>   (`031fe941…`) is not what executes here. The reversion risk below is observed, not predicted.
>
> **TRANSPORT (2026-08-01).** The commit carrying this paragraph re-applies `f018623` +
> `ab8055b`'s claim-corrections and the defect-4 fix onto master's evolved copy, and adds the
> in-suite regression pin both commits admitted was missing (RPL9-RPL9g, see the Proven-by
> block below). It is a builder-branch commit: the heading's "still NOT MERGED" is true as
> written and flips only when this lands on master.
>
> **THE INSTALL IS REVERSIBLE AND WILL BE REVERTED — merging is what makes it durable.**
> `session-start-auto-install.sh` is **master-wins for `hooks/*.sh`** (its own self-test
> scenarios L4/L6 assert precisely that), so the **next SessionStart silently copies master's
> UNFIXED content back over the fixed live hook** and the eternal-green defect returns with no
> warning and no diff anyone is watching. The hand-install buys quiet only until the next
> session starts. **Nothing here is safe until this lands on master.**
>
> The original point still stands for the *cockpit*: the running harness executes
> `~/.claude/hooks/`, not the repo, so "the greens will age out" is measured from INSTALL,
> never from commit — and that clock resets every time auto-install reverts the file.

**Severity:** HIGH. Emitter fix WRITTEN (see below); the entry stays OPEN both because the fix
is not yet live AND because the honest replacement signal then depends on `NL-ATTRIBUTION`
header adoption, which sits in a LOW BAND (see `NL-ATTRIBUTION-ADOPTION-12-PERCENT-01` for why
no single percentage is quotable — the log rotates, so the denominator is not monotonic).
(Operator-reported: "The green items are supposed to indicate something is actively running.
I see several green plans that aren't running.")

**SECOND CORRECTION 2026-07-30 (builder, independent re-derivation from the raw data — the
refutation below got the DIRECTION right and the MECHANISM wrong):**
- The refutation's claim "ONE Task dispatch produced 42 markers" is NOT what the data shows.
  MEASURED from `~/.claude/logs/conversation-tree-emit.log`: that window
  (22:16:59Z-22:18:06Z) contains **100 separate `--on-builder-dispatch` hook fires**, not one.
- WHAT THEY ACTUALLY ARE (PROVEN): the fires walk
  `~/.claude/state/conversation-tree-emit/builder-a3fcb6ea-….jsonl` **in ledger order from
  index 0** — beginning with "Verify T3 admission lib", whose real tool call happened
  **2026-07-29T03:12:13Z, 43 hours earlier** — with exactly 2 genuinely-new dispatches
  (ledger idx 103, 104) spliced in. PreToolUse **re-fires for every historical Task/Agent
  tool call in the transcript**. Five such replays on 2026-07-30 (21:11, 21:32, 21:36,
  22:17, 22:28), each re-emitting `task_started` for every plan/task any prompt in 43h of
  history ever named. THAT is why plans stayed green with nothing running.
- The single-`child_id` observation is real but proves nothing about fan-out:
  `child_id = "ss-" + sha1(session_id)`, so EVERY dispatch from one session shares it by
  construction. It is a session id, not a dispatch id.
- BOTH defects were live and BOTH had to be fixed. Mention-scraping alone explains the
  wrong-task attribution; replay alone explains the eternal re-greening. Fixing only the
  first would have left the observed incident **100% intact** — counterfactual over the five
  measured bursts: 468 fires, 60 of them `attributed=1`, but **0** were first-fires of their
  dispatch identity, so a header-only fix emits 0 of the 95 spurious events and also 0 of the
  real ones. Every task_started emitted in those five bursts was spurious.

**THE FIX — WRITTEN 2026-07-30, NOT MERGED, NOT INSTALLED** (`adapters/claude-code/hooks/workstreams-emit.sh`): the two sinks
inside `_emit_dispatch_provenance` were one code path and are now separated, because they are
not the same kind of claim — `task_started` is a claim about the PRESENT that the operator
reads as a green chip, while the dispatch-provenance marker is a correlation hint for
`pl_classify_session`. `task_started` now requires BOTH:
1. **Header-authoritative attribution.** Only `NL-ATTRIBUTION: plan=… task=…` may name the
   task that started. `_extract_plan_slug`/`_extract_task_id` are no longer a source of
   `task_started` at all. A mention is not a dispatch.
2. **First fire of the dispatch identity.** `item_id = sha1(sid|tool|title)` (deliberately
   time-bucket-free) already has first-seen semantics in the builder correlation ledger; that
   ledger read is now load-bearing. A fire for an identity already recorded is a transcript
   replay, not a start. Correct from the first fire after install — the ledger already holds
   the session's history, so no warm-up period. The spawn surface got the same treatment
   keyed on `(child_id, title)`, plus the `NL-ATTRIBUTION` parse it never had.
   **THE IDENTITY LEDGER MUST OUTLIVE THE TURN (second pass, 2026-07-30).** The spawn half of
   this gate first keyed on `opened-<sid>.jsonl` — the CONCLUDE ledger, which `--on-stop`
   deletes at every turn boundary and `--heartbeat` deletes on staleness. PROVEN by executed
   trace: first spawn → 1 event; replay with no Stop → still 1 (gate holds); ledger dir after
   `--on-stop` → empty; replay after `--on-stop` → **2** — i.e. the "first fire only"
   guarantee this entry claimed evaporated one turn after being set, and the eternal-green
   defect was still fully live on the spawn surface while the code, the commit message, the
   doctrine, the manifest AND this entry all said it was fixed. A dispatch-identity SET and a
   conclude QUEUE have different lifetimes, so they are now different files: `spawn-<sid>.jsonl`
   is append-only and deleted by nothing, matching `builder-<sid>.jsonl` (which is why the
   builder surface never had the hole). Pinned by RPL6/RPL6b/RPL6c.
3. **The header must OPEN the dispatch, not merely appear in it** (second pass, 2026-07-30).
   The parse matched `NL-ATTRIBUTION:` ANYWHERE in the joined prompt text, so a **QUOTED**
   header was indistinguishable from a real one: a prompt merely DISCUSSING a prior dispatch
   ("…it was dispatched with the line `NL-ATTRIBUTION: plan=X task=9 role=builder` and it
   failed") emitted a real `task_started` for task 9. That is the SAME mention-is-not-a-dispatch
   defect this entry exists for, surviving inside the source the fix had just declared
   authoritative — and a LIVE vector, since handoff/review/post-mortem prompts routinely paste
   the builder prompt they are about. The header must now start a line AND sit within the first
   `NL_ATTRIBUTION_MAX_LINE` (default 5) lines **of the JOINED `prompt + description + content`**
   (NOT of the prompt alone — see the residual note below), which is what
   `doctrine/orchestrator-pattern.md` already required in words ("MUST open with"). Pinned by
   RPL7/RPL7b, with RPL7c pinning that a real dispatch is not collateral damage.
No-header policy is **honest silence**: an unattributed event names no task, so it can turn no
chip green — it could only pollute the orphan lane (the
`PROGRESS-LOG-ID-JSONL-UNACCOUNTED-01` class), and the WARN counter already logs every
unattributed dispatch with a running total. Falling back to scraping was never an option:
scraping is the bug.
**Proven by** (every figure below RE-EXECUTED at the current HEAD, not carried forward — see
the standing rule at the end of this block): `workstreams-emit.sh --self-test`
**120 passed / 1 failed**, identical on BOTH `/bin/bash` (3.2.57) and
`/opt/homebrew/bin/bash` (the 1 is pre-existing ST11, failing identically at baseline 92/1);
**+28 executing assertions over baseline** (PL1a, PL1d, RPL1-RPL8b) — never a regex over
source text, every one drives the real hook. Siblings green on both interpreters:
`progress-log-lib.sh` 48/0, `dispatch-provenance.sh` 17/0; Node `roadmap-routes` 116/0,
`derive-lib` 65/0. **Mutations — every kill set non-empty, and identical on both
interpreters:**
| mutation | kill set at HEAD | suite |
|---|---|---|
| M1 restore-the-scrape | PL1, RPL3, RPL4 | — |
| M2 scrape-beats-header | PL1, RPL1b, RPL1c, RPL3, RPL4 | — |
| M3 replay-gate-off | PL1d, RPL2b, RPL2c, RPL5b | — |
| M4 spawn-gate-keyed-on-the-deleted-ledger | RPL6b, RPL6c | 118/3 |
| M5 header-matched-anywhere | RPL7, RPL7b, RPL7e, RPL7g, RPL7h, RPL7j | 114/7 |
| M5b line-start-kept / window-removed | RPL7b, RPL7e, RPL7j | 117/4 |
| M5c window-kept / line-start-removed | RPL7, RPL7g, RPL7h | 117/4 |
| M6 awk-field-equality → `grep -qF` | RPL8, RPL8b | 118/3 |
| M8 TIGHTENING (window → 2 *or* → 1) | RPL7d, RPL7f, RPL7i | 117/4 |
M5b + M5c prove EACH HALF of the anchor is independently load-bearing. M8 is the opposite
direction: loosening reddens six scenarios, tightening reddens the three that assert the
residual, so the residual cannot move silently either way. (M1-M3 predate the per-mutation
suite-count capture and are listed by kill set only.)

> **EVERY FIGURE IN THIS BLOCK IS A DATED SNAPSHOT, NOT A PRESENT-TENSE CLAIM — applying
> this entry's own STANDING RULE (below) to itself, 2026-08-01.** The `120 passed / 1 failed`
> baseline and the whole `suite` column above were measured on the AUTHORING machine (macOS,
> both interpreters) at commit `ab8055b`. That suite no longer exists: master's copy diverged
> (attribution pipeline, PL4e, the 120s debounce) and the transport commit then added 8 more
> assertions, so **every total in the table is invalidated — including by this very commit,
> which is exactly the failure mode the rule names.**
>
> **Re-executed on the TRANSPORT machine (Windows/Git-Bash, `/usr/bin/bash`), 2026-08-01:**
> `HARNESS_SELFTEST=1 bash adapters/claude-code/hooks/workstreams-emit.sh --self-test`
> -> **131 passed / 0 failed**, `self-test: OK`. (Note the `1 failed` above is gone: master's
> ST11 passes here.) That is the merged-tree baseline **123/123** plus the **8** new
> defect-4 assertions RPL9-RPL9g. **+36 executing assertions over the original baseline**
> (PL1a, PL1d, RPL1-RPL8b, RPL9-RPL9g).
>
> **NOT RE-EXECUTED, AND SAID SO RATHER THAN QUIETLY RESTATED:** the per-mutation `suite`
> column (M4 118/3, M5 114/7, M5b/M5c/M8 117/4, M6 118/3). Re-running nine mutations x a
> full suite is hours on this fork-taxed target and was not done, so those totals are marked
> STALE at their measurement point rather than carried forward as current. The **kill sets**
> are NOT invalidated — no scenario in them was renamed, removed or altered by the transport,
> and RPL9-RPL9g touch a different mechanism (the ledger WRITE's failure path) than any
> mutation in the table (the header anchor and the gate's identity key).
>
> **ONE INTERPRETER ONLY.** The two-interpreter claim above does NOT extend to the 131/0
> figure: this machine has no second bash, so `/bin/bash` 3.2.57 (the portability floor named
> in `docs/TAKEOVER-2026-07-31.md` §7) is UNVERIFIED for the transported content.
**STANDING RULE, learned the hard way three times in this entry (F8, then the M8 kill set,
then this block): a numeric claim about a suite is invalidated by ANY change to that suite —
INCLUDING one's own. Every commit that adds or renames an assertion must, in the same commit,
re-run and restate every count and every kill set in every artifact quoting one.** The
recurring failure was always the same shape: a figure measured at the PARENT commit, restated
as current. Concretely, this block once read 113/1 and "M5b → RPL7b only" — both true at
`d0430ca`, both false the moment RPL7e/RPL7i/RPL7j were added.

**RESIDUAL — WHAT IS STILL WRONG AFTER THIS FIX (honest):**
- **AN UNWRITABLE LEDGER STILL FAILS OPEN — the defect-4 fix made it LOUD, not SAFE**
  (measured 2026-08-01, now pinned by RPL9c). If the replay gate's own state write fails
  (`LEDGER_DIR` unwritable while `LOG_DIR` still works), the identity is never recorded,
  every later fire re-decides `dispatch_is_new=1`, and **the duplicate `task_started` IS
  re-emitted** — this entry's own eternal-green defect, live. Executed RED/GREEN, ledger path
  pre-created as a directory so the append fails: master's pre-fix copy logged `replay=0`
  twice with ZERO warnings while emitting 2 events; the fixed copy emits the same 2 events
  but logs a WARN naming `ROADMAP-FALSE-ETERNAL-RUNNING-01` on every fire and reports
  `replay=?` instead of a confident `0`. So what the fix bought is that the dead gate can no
  longer be read off the log as a healthy one — **not** that the gate survives. The direction
  is DELIBERATE: this is a WRITER hook that never blocks, so suppressing on a failed write
  would trade a visible duplicate for an invisible missing green. RPL9c is where a future
  change of direction has to be re-argued. **Next action if this ever bites in the wild: a
  durable identity store outside the ledger, which is new machinery and needs its own
  constitution §10 evidence bar first.**
- **The cockpit now UNDER-reports, and this is the big one.** Only a LOW BAND of dispatches
  carry an `NL-ATTRIBUTION` header, and the WARN counter only climbs — see
  `NL-ATTRIBUTION-ADOPTION-12-PERCENT-01` for the measurement commands and why a single
  percentage is NOT quotable here (the log rotates). Real work in progress will show NOTHING
  until orchestrators actually emit the header that `doctrine/orchestrator-pattern.md` already
  calls MANDATORY. Silence is the correct direction (a missing green is not a lie) but it is
  not the destination. **Next action: make the header a dispatch-time requirement, not a WARN.**
- **No END signal at this layer.** The fix stops re-greening; it adds no "task stopped" event.
  A green still ages out only via the downstream 60-min `taskStartedIdleMs`
  (`derive-lib.js:690`, `:914`), so a genuinely-finished task stays green for up to an hour.
- **Accepted cost:** a genuine re-dispatch reusing an IDENTICAL (session, tool, title) emits no
  second `task_started` — indistinguishable from a replay at PreToolUse. Errs toward a missing
  green over a false one. Pinned by scenario PL1d. All 105 identities in the operator's real
  43h ledger have distinct titles, so the empirical cost today is zero.
- **No one-shot cleanup of stale rows is required** (checked, not assumed): green is gated on
  `startedAtMs` being within `taskStartedIdleMs` (60 min default, `derive-lib.js:690`), so
  spurious rows age out on their own once **no new ones are emitted**. The 1394 historical
  `task_started` rows can stay; they are inert to the green chip.
  **CORRECTED 2026-07-30 — the earlier "they age out within an hour of the last replay
  (22:29:23Z)" was WRONG, and wrong in the direction that flatters the fix.** 22:29Z was not
  the last replay; it was merely the last one that had happened when the sentence was written.
  PROVEN from `~/.claude/logs/conversation-tree-emit.log`, minute-bucketed: bursts continued at
  **22:44-22:46Z (711 fires), 23:26-23:28Z (739), and 23:39-23:40Z (723)** — at least three
  more after the cited "last" one, on top of the five already counted. **The clock does not
  start at the last observed replay, and it does not start at commit: it starts at INSTALL.**
  Replays keep firing the OLD hook until `install.sh` copies the new one into `~/.claude/`,
  which happens only after this merges to master. Any "N minutes until the cockpit is honest"
  estimate must be measured from that moment.
  HYPOTHESIZED (not runtime-verified — no cockpit instance was exercised from this worktree):
  the operator's live cockpit goes quiet ~60 min after the last replay THAT FOLLOWS INSTALL.
  REFUTED BY: a green chip persisting past that with no `task_started` newer than 60 min for
  its task.
- **The replay gate is per-session and per-ledger-file, and both are defeatable** (disclosed
  after an adversarial refutation executed them, 2026-07-30 — neither is a regression, both
  were always true and were simply never written down):
  (a) **A NEW `session_id` re-emits every identity.** The gate key includes the session id, so
  replaying the same dispatch identities under a fresh session id emits them all again
  (measured 4 → 8). This is by construction — a genuinely new session dispatching the same
  work IS a new start — but it means a session-id churn (resume, re-attach, a new window over
  the same transcript) can re-green tasks. Not currently distinguishable at PreToolUse.
  (b) **Deleting the identity ledger re-emits.** Removing `spawn-<sid>.jsonl` /
  `builder-<sid>.jsonl` and replaying emits again (measured 1 → 2). The ledger is now
  deleted by no code path in this repo (that was the F1 fix), so this requires external
  removal — but it means the gate's durability is exactly the durability of
  `~/.claude/state/conversation-tree-emit/`, which nothing guarantees against manual cleanup,
  tmp-reaping, or a machine migration.
- **The header's positional anchor is a heuristic, and the residual is WIDER than this entry
  first claimed** (restated 2026-07-30 from the EXECUTED boundary after a harness-reviewer
  REFORMULATE; the earlier "a paste must be the first thing in the prompt" was understated,
  and its doctrine counterpart — "a quoted header below the prose that introduces it is
  inert" — was outright FALSE and is retracted). **TRUE RESIDUAL: any quoted header that
  STARTS A LINE — with arbitrary leading whitespace, including the indentation a fenced or
  indented paste adds — anywhere within the first `NL_ATTRIBUTION_MAX_LINE` (default 5) lines
  **of the JOINED `prompt + description + content`** still emits a real `task_started`.**
  PROVEN against the shipping parser: 2-line preamble + fenced paste → EMITS; 4-space-indented
  paste → EMITS; TAB-indented header on line 2 → EMITS; 3-line preamble + fence (header on
  line 5, the last admitted line) → EMITS. Silent: header on line 6+ (RPL7e), `> ` prefix
  (RPL7g), `- ` prefix (RPL7h).
  **THE WINDOW IS OVER THE JOINED TEXT, NOT OVER THE PROMPT** (corrected in round 3; every
  earlier statement here said "the first 5 lines of your prompt", which is advice an author
  cannot act on). `_dispatch_text` (in `adapters/claude-code/hooks/workstreams-emit.sh` — cited
  by SYMBOL, not line number, because the same commit edits that file and a line citation goes
  stale the moment it does; it was written as `:3110` and was already wrong by one edit) joins `[prompt, description,
  content]` with newlines BEFORE the window applies, so the admitted region spans a SECOND
  INPUT FIELD whenever the prompt is short: a 3-line prompt with the header alone in
  `description` lands on JOINED line 4 and EMITS (RPL7i), while the same description behind a
  10-line prompt is silent (RPL7j). Same field-scope error class as F2 itself, one level up.
  **Operative rule for authors quoting a header: keep it below line 5 of the JOINED text AND
  out of the `description` field of a short-prompt dispatch — or just prefix it with `> ` /
  `- `, which is robust because it does not require counting lines across three fields.** This
  matters because it is the shape of a REAL handoff/review prompt (short preamble, then a
  fenced paste), not an exotic one, and the failure direction is a FALSE green — the one
  remaining known path to the original defect. Closing it needs an out-of-band field the prose
  cannot forge, unreachable from PreToolUse `tool_input` today.
  **HOW THE UNDERSTATEMENT SURVIVED, recorded because the mechanism generalizes:** scenario
  RPL7b passes with a preamble that happens to run EIGHT lines — comfortably past the 5-line
  window — so it certified a general claim it only tested one side of. Class:
  *understated-residual-certified-by-a-window-tuned-test*. **Standing rule adopted: every
  threshold or positional guard ships a negative case ADJACENT to the threshold (n-1, n, n+1),
  never one comfortably beyond it, and the prose residual is written from the executed
  boundary rather than the motivating anecdote.** Now pinned by RPL7f/RPL7d/RPL7e.
  **The residual is pinned in BOTH directions**, so it cannot drift silently either way
  (kill sets RE-EXECUTED at HEAD, identical on both interpreters): loosening the anchor
  reddens RPL7/RPL7b/RPL7e/RPL7g/RPL7h/**RPL7j** (M5, 114/7; M5b → RPL7b/RPL7e/RPL7j, 117/4;
  M5c → RPL7/RPL7g/RPL7h, 117/4), and TIGHTENING it reddens the three residual-asserting pins
  RPL7d/RPL7f/**RPL7i** (M8, 117/4).
  **TIGHTENING LEVER — evaluated at 5 / 2 / 1, decision recorded (round 3).** Measured at
  HEAD, both interpreters: `NL_ATTRIBUTION_MAX_LINE=2` and `=1` each redden **exactly
  RPL7d + RPL7f + RPL7i** and nothing else — identical kill sets, **117 passed / 4 failed**
  (the fourth being pre-existing ST11). *(This figure was previously written as "RPL7d+RPL7f,
  116/3" — true at `3c18c0d`, wrong at HEAD, because the very commit that recorded it added
  RPL7i, which asserts EMISSION at joined line 4 and therefore reddens under any tightening.
  Same measurement-from-a-prior-commit class as the F8 retraction; see the standing rule in
  the Proven-by block above.)* **`=2` was the missing middle option:** an earlier
  revision of this entry framed the choice as 5-vs-1, which was a false dichotomy — `=2`
  eliminates the fence-paste shapes that land at joined lines 3-5 while still admitting the
  one cost case that argued against `=1` (a real header under a title or blank line).
  **DECISION: keep the default at 5 for now, and sequence the tightening AFTER a header
  constructor exists.** Reasoning: the cost of tightening is genuinely UNMEASURABLE today —
  header POSITION is not recorded in the emit log, so there is no way to count how many real
  dispatches would fall outside a 2-line window; once a constructor emits the header, position
  becomes uniform by construction and the cost goes to zero, at which point `=2` (or `=1`) is
  free. Tightening first would trade a measurable false-green reduction for an unmeasurable
  missing-green increase, against an adoption rate already in the low band
  (`NL-ATTRIBUTION-ADOPTION-12-PERCENT-01`).
  **UPDATE 2026-08-03 (Task 15 / REQ-B14, gated-pipeline-master-2026-08.md — G2's named
  residual "the known quoted-header parse quirk is fixed in a parse shared with
  workstreams-emit"): PARTIALLY CLOSED, WIDTH decision above UNCHANGED.** `_extract_nl_attribution`
  gained two guards orthogonal to `NL_ATTRIBUTION_MAX_LINE` (still 5, per the decision above,
  still deferred until a header constructor exists): (1) column-0-only — the header line
  itself may carry no leading whitespace; (2) fence-precedence rejection — a header whose
  immediately preceding line opens/continues a code fence is quoted, not a dispatch. This
  closes the two CONCRETELY MEASURED shapes RPL7f (indented paste) and RPL7d (fenced paste)
  probed — both scenarios flipped from asserting EMIT to asserting REJECT in the same commit
  that made this change, per their own standing instruction. NOT closed: RPL7i's shape (a
  header at column 0, no fence, directly below a colon-terminated prose line) — still asserted
  EMIT deliberately. Closing that residual still needs either the width-tightening this
  decision defers, or an out-of-band field unavailable from PreToolUse `tool_input` today.
  Round-trip test evidence: `adapters/claude-code/hooks/workstreams-emit.sh --self-test`
  140/140 (was 131/131 baseline, +9 new: DL1-DL7 dispatch-ledger writer scenarios, Task 15's
  OTHER deliverable, landed in the same commit).
  **FRAMING ERROR CORRECTED:** the previous revision called this "an operator call, not a
  builder's". That was wrong — a one-line-reversible env default is **decide-and-go under
  constitution §8** (undoing it is a single edit), so it is mine to decide with a trail, which
  is what this paragraph now is. The operator-call framing was permission-seeking dressed as
  deference.
- **`harness-doctor.sh --quick`: the RED set is UNCHANGED by this work — 17 red / 8 warn at
  both `17c0d4c` and `d0430ca`, identical RED names, empty diff** (corrected 2026-07-30 by an
  independent harness-reviewer measurement; my original "13 RED → 14 RED, one added" was
  WRONG). **Why mine was wrong, recorded because the class recurs:** I measured baseline and
  after at DIFFERENT TIMES in a live worktree, via `git stash` / `git stash pop`. But
  `manifest-freshness` compares the LIVE `~/.claude/manifest.json` against the repo tree, and
  the live copy is continuously re-synced from origin/master by
  `session-start-auto-install.sh` — so it is a MOVING TARGET, not a constant, and any
  before/after separated in time silently attributes environment drift to the change. The
  controlled measurement (both refs checked out back-to-back in ONE isolated clone) shows
  `manifest-freshness` was ALREADY RED at baseline: the live manifest (`cc53eea6`) matches
  NEITHER tree. **Class: environment-coupled metric reported as a controlled delta.** Standing
  rule: a metric that reads state outside the repo cannot be A/B'd across time in a live
  checkout — check both refs out back-to-back in one clean clone, or do not claim a delta.

**FIRST CORRECTION 2026-07-30 (adversarial refutation, agent a7b621c3, verdict PARTIAL — the
earlier "FIXED this build" claim in this entry was FALSE and is retracted; this correction's
own mechanism claim is in turn corrected above, though its "stop scraping the prompt text"
prescription was right):**
- The live app STILL renders all three operator-reported tasks green (verified 22:24:52Z against
  the shipped 60-min default, server PID started after the commit) — including
  `cockpit-roadmap-redesign/9`, an Acceptance task requiring the OPERATOR'S OWN walkthrough,
  which no agent can ever be running.
- REAL ROOT CAUSE (PROVEN, and NOT what this entry originally claimed): `task_started` is
  emitted per MENTION, not per DISPATCH. `workstreams-emit.sh --on-builder-dispatch` scrapes
  plan slugs and task ids out of the dispatch PROMPT TEXT, so an orchestration prompt that
  merely NAMES a task marks it started. Measured: ONE dispatch at 22:17 produced 42 provenance
  markers across 15 distinct (plan,task) pairs and 20 task_started events, all sharing
  child_id ss-69752570c1d6 — ~14 of the 15 tasks were never dispatched at all.
- THEREFORE NO TIME WINDOW CAN WORK: spurious and genuine events are literally the same events
  fanned out from one dispatch. Quantified over the operator's waking window (16:00-22:17Z):
  72.7% green WITH the fix vs 100% without, and the entire suppression is the single 163-min
  gap that was the reported incident; every other gap all day is under 60 min.
- THE PREVIOUSLY-FILED REFUTER ("record the dispatched CHILD's session id") ALSO FAILS by
  construction: all 15 pairs share one child_id, so it would attach one child session to
  fifteen unrelated tasks.
- CORRECT FIX (upstream, not downstream): `--on-builder-dispatch` must emit exactly ONE
  task_started for the task actually dispatched — the `NL-ATTRIBUTION` header already carries
  it (`_extract_nl_attribution` in workstreams-emit.sh — cited by symbol; the original
  `:2001` line citation is long stale, this file having been edited many times since) —
  instead of one per prompt-text mention.
- WHAT DID LAND AND IS KEPT: the rollup gate (`live_sessions.length` -> `hasRunningLeaf`) is an
  unambiguous correctness improvement independent of the window, mutation-proven (3 disjoint
  mutations each kill the correct disjoint test subset), and demonstrably fires in production.
- ALSO CORRECTED: the commit trailer's `Live-demonstrated:` line was produced with
  COCKPIT_TASK_STARTED_IDLE_MIN=5, a 12x tighter window than ships — disclosed in this entry,
  not in the trailer where the claim was made.
- Threshold evidence understated: the 60-min bound was justified from a cherry-picked 50-min
  stretch (max gap 12 min); over the full active window real gaps reach 41.1 min, so the true
  margin is 1.46x, not 5x.

**FOLLOW-ON 2026-07-30 (harness-reviewer REJECT on `ebc9a12`, all findings closed — see the
commit that adds this block):** the reviewer's verdict was that the server-side work was sound
but *did not close the operator's reported symptom*. Five defects closed:
1. **The green chip was still painted (CRITICAL).** `web/roadmap.js`'s `taskSpanCell` used the
   IDENTICAL `live_sessions.length` membership predicate that had been fixed server-side, so
   every TASK row (including `cockpit-roadmap-redesign/9`, the operator's headline example)
   kept its green chip. PLAN rows were never affected (they read the server's verified
   `roll_up.running`). Swept all four client sites the reviewer named: 724 chip (FIXED),
   813 "currently running (N)" header (FIXED — it counted stalled leaves), 1333 `nodeIsActive`
   auto-expand (FIXED), 1979 unbound-sessions gate (AUDITED, deliberately unchanged — that
   collection is server-filtered and stamps members `in-progress`, so applying the predicate
   would hide genuinely-running work; the audit note lives with the code and is pinned by a
   test). Class: **non-empty-collection-as-truth-claim**.
2. **The fix introduced a NEW false claim (MAJOR).** `startedIdleExpired` was folded into the
   `crashed` reason, so a task whose session had a heartbeat written seconds earlier rendered
   "stalled — crashed" and rolled a `crashed` badge up to its plan — pointing the operator at
   a dead-process investigation that did not exist (constitution §1). Split out a distinct
   `idle-dispatch` reason with its own precedence slot (ranked LAST among stalled reasons:
   any specific known cause must outrank the weakest "nothing happened lately" one) and its
   own label/CSS. Class: **reason-code-reuse-misattribution**.
3. **The retraction above had landed in this ledger but NOT in the source (MAJOR).**
   `derive-lib.js`'s threshold header still argued the discredited "~12min gap / 50-minute
   stretch / ample margin" case. Rewritten to the re-measured distribution and labelled
   PROVISIONAL. Class: **correction-landed-in-one-artifact-only** — when retracting a claim,
   sweep every artifact carrying it, not just the ledger.
4. **The threshold is calibrated on the corrupted telemetry it exists to compensate for
   (MAJOR, HYPOTHESIZED).** Now stated in the header itself. **OPEN FOLLOW-UP: re-derive
   `taskStartedIdleMs` once `--on-builder-dispatch` emits one event per real dispatch.** Until
   then the default is provisional and may be too tight — a task genuinely worked >60 min on a
   single dispatch will render 'stalled' (a false NEGATIVE the upstream fix will introduce).
   REFUTED IF a post-fix scan shows the >60min share of same-task gaps materially unchanged
   (~3%). Class: **threshold-calibrated-on-corrupted-telemetry**.
5. **Malformed evidence conflated with absent evidence (MAJOR, fail-open).** A PRESENT-but-
   unparseable `task_started.ts` collapsed to `null`, silently disabling the idle gate and
   restoring green-forever on exactly the least trustworthy input. The heartbeat side already
   handled its own unparseable timestamp correctly; the asymmetry is closed — both now render
   `unknown`. Class: **fail-open-on-unreadable-input**.
Plus two MINORs (partial `thresholds` override now MERGES over complete defaults instead of
NaN-disabling the gate; `startedIdleExpired` is present on every `deriveItemStatus` return
instead of relying on a non-local invariant in another function).

**Re-measured gap distribution (2026-07-30, `~/.claude/state/progress-logs/*.jsonl`):** 151
files, 1617 `task_started`, 1596 same-task gaps. p50 4.4min / p90 17.4min / p95 41.1min;
largest sub-threshold gap 49.1min; **49 gaps (3.07%) exceed 60min**, another 48 in 30-60min.
Busiest single minute: 18 distinct task keys (the fan-out signature). This independently
reproduces the reviewer's scan and is what the source header now cites.

**Two defects found BY the new tests while closing the above (both fixed in the same commit):**
- `roadmap-routes.js` kept a hand-maintained duplicate of `ATTENTION_PRECEDENCE`
  (`ROLLUP_CLASSES`) AND fell back to `'blocked-on'` for any reason class it did not
  recognise — so the new `idle-dispatch` code silently rolled up as "stalled — blocked on a
  predecessor", a fabricated dependency claim. `ROLLUP_CLASSES` is now DERIVED from
  derive-lib, and the fallback is `'unknown'` (honest) rather than a specific wrong claim.
  Class: **duplicated-vocabulary-with-misattributing-fallback**.
- A task deriving `unknown` still emitted `running` session leaves off the heartbeat alone,
  and its plan then rolled up a green "1 running" badge for a task the server had just
  admitted it could not classify. `deriveLiveAgentLeaves` now takes the task's own derived
  status and can only ever narrow it. Class: **leaf-contradicts-its-own-parent-status**.

**Minor, NOT fixed (deliberate scope hold):** the drill-down reason row renders the raw code
("stalled: idle-dispatch"), consistent with how every other reason code renders there. The
full human phrasing is already carried by the adjacent badge label and the session leaf, so
this is terse rather than misleading. Worth a consistent reason-phrase pass across all five
codes if the vocabulary grows again.
**Root cause, PROVEN against real deployed data (2026-07-30):** `roadmap-routes.js`'s
`absorbOneChildRollUp` rolled a task up as `running` whenever `child.live_sessions.length` was
merely non-empty — independent of whether the attached session's heartbeat was actually fresh.
Deeper cause: a `task_started` event's `session_id` field records the **dispatching**
(orchestrator) session, never a distinct per-task worker session — and an orchestrator session
commonly stays heartbeating for many hours across dozens of unrelated dispatches, so "the
attached session is alive" can never by itself prove THIS task has current activity. Real
progress-log evidence: `progress-log-placeholder-ask-id-fix/4`, `status-event-ledger/SE3`, and
`cockpit-roadmap-redesign/9` all rendered `running` for a 2h43m gap (16:57Z-19:40Z) during which
the SAME dispatching session (`a3fcb6ea-...`) never touched any of them but stayed alive doing
unrelated estate work.
**Fix (this build):** `deriveLib.deriveItemStatus` gained a `startedAtMs`/`taskStartedIdleMs`
axis (default 60min, env `COCKPIT_TASK_STARTED_IDLE_MIN`) — a task_started event older than the
window no longer renders in-progress even with a live attached-session heartbeat.
`deriveLiveAgentLeaves` and `absorbOneChildRollUp`'s rollup gate (the reported line) now both
require an ACTUALLY-running leaf, not merely a non-empty array. Proven two ways: (1) unit —
`derive-lib.js --self-test` 7i-7n, `roadmap-routes.selftest.js` S20c-e, all RED-then-GREEN
verified against the real bug; (2) live — a temporary side-by-side instance (`CTREE_PORT=7799`,
reading the REAL `~/.claude/state/progress-logs` + heartbeats, `COCKPIT_TASK_STARTED_IDLE_MIN=5`
for the demo only) flipped the exact 3 reported tasks from `running`/`in-progress` to
`stalled`/`crashed` while the same production instance (:7733, unfixed) still showed `running`
for the same tasks at the same real timestamps.
**Residual gap (HYPOTHESIZED, not fixed this build):** the idle-window is a mitigation, not a
structural fix — it bounds trust in a signal that is still architecturally the wrong one
(dispatching-session heartbeat, not per-task-worker heartbeat). A task genuinely re-dispatched
(or swept/nudged) more often than the idle window, with no real work happening between
dispatches, would still show `running` forever under this fix, exactly as observed live today:
at demonstration time, an ongoing estate-wide sweep was re-touching these same 3 tasks roughly
every 13-16 minutes (task_started re-fired at 19:40, 19:56, 20:09), which is inside the 60min
default window, so the CURRENT live snapshot still (correctly, per the fix's own logic) shows
them running — the fix could only be shown flipping the reported instance by temporarily
shrinking the window for the demo. REFUTED by: recording the dispatched CHILD's own session id
(not the dispatcher's) in `task_started`'s `session_id` field and deriving from ITS heartbeat —
would require dispatch-provenance.sh to learn the child's session id before/at dispatch time,
which it does not currently have (the child session doesn't exist yet at PreToolUse time). Out
of scope for this task; flagged for a future round.
**Filed by:** plan-phase-builder, false-eternal-running-fix build, 2026-07-30.

## NL-ATTRIBUTION-ADOPTION-12-PERCENT-01 — the honest green signal now depends on a header almost nobody sends

**Severity:** HIGH, OPEN. Direct consequence of ROADMAP-FALSE-ETERNAL-RUNNING-01's fix above.

**THE PERCENTAGE IS NOT A STABLE FACT — DO NOT QUOTE ONE** (this rule is stated FIRST,
deliberately: an earlier revision put a headline `~12%` above it and then left two more copies
elsewhere in this file, which is a rule its own document violates and therefore teaches
nothing). FOUR readings the same day, each correct when taken: ~12% (12 of 103 distinct
identities in one window, WARN 4090), 10.2% (822/8081 lines, WARN 5146), 13.8% (899/6522,
independent reviewer, WARN 5623), 10.6% (960/9084, WARN 6011). They disagree partly on
numerator/denominator choice and partly because **`~/.claude/logs/conversation-tree-emit.log`
ROTATES — the denominator is not monotonic**, so a later reading can legitimately be over a
SMALLER log. Record the command and BOTH terms, never a bare rate:
```
L=~/.claude/logs/conversation-tree-emit.log
grep -c 'builder-dispatch item=' "$L"                          # denominator (rotates!)
grep 'builder-dispatch item=' "$L" | grep -c 'attributed=1'    # numerator
grep -o 'unattributed dispatch #[0-9]*' "$L" | grep -o '[0-9]*' | sort -n | tail -1
```
All readings agree on the only durable conclusion: **adoption sits in a low band (roughly
10-14%) and the WARN counter (4090 → 4963 → 5146 → 5623 → 6011 across the day) only climbs.**

**RETRACTED 2026-07-31 — "the WARN series survives log rotation, while the rate does not."**
That claimed an asymmetry that does not exist, in the same entry that correctly says the log
rotates. PROVEN false by reading the implementation: the counter is
`grep -c 'WARN unattributed builder dispatch' "$LOG_FILE"` (`workstreams-emit.sh`, in the
`--on-builder-dispatch` WARN block) — a **line count over the very file** whose line count is
the rate's denominator. Numerator and denominator share one file, so they share its fate: if
that file is truncated, rotated or deleted, **both** restart. The WARN series is not
rotation-proof and is not more durable than the rate.

The honest property: it is a **whole-file running total, monotonic only within one log file's
lifetime**. Two further corrections in the same breath — (a) it has **no session predicate**,
so it is a total across ALL sessions, not per-session (13 distinct `session=` values were
feeding one series when this was caught; the message wrongly said "logged this session" and is
now relabelled); (b) **nothing in this harness currently rotates
`~/.claude/logs/conversation-tree-emit.log`** — `grep -rn 'rotate'` over `adapters/` finds
rotation machinery only for the admission ledger, supervisor tick and coord-sync logs, never
this one. That is an *absence of machinery*, not a durability guarantee, and it does not
resurrect the retracted claim: a manual `rm`/truncate resets the counter just the same.

**If a genuinely monotonic adoption metric is ever needed**, it requires a durable counter
kept OUTSIDE the log (its own state file, incremented and read independently of `$LOG_FILE`).
That is a new mechanism and, per constitution §10, would need its own golden scenario,
expected false-positive behaviour and retirement condition before it lands. It was
deliberately NOT built here — this pass retracts a false claim rather than shipping unproven
machinery to justify it.

**THE ADOPTION MECHANISM DOES NOT EXIST — this is the load-bearing finding, not the
percentage.** `grep -rn 'NL-ATTRIBUTION'` over `agents/`, `templates/`, `skills/`,
`commands/`, `hooks/` and `scripts/` returns **ZERO constructors**: the only matches are the
PARSER (`hooks/workstreams-emit.sh`) and two consumers (`hooks/lib/admission-lib.sh`,
`scripts/dispatch-provenance.sh`). **No harness surface emits the header.** Every dispatch
prompt that carries one carries it because a human or an agent typed it from memory of a
doctrine file. So adoption has no mechanical carrier, and the WARN counter can only climb —
which makes this a textbook constitution §10 case: a documented convention with no mechanism
is not a mechanism, and a WARN ignored 5146 times is not enforcement. **The fix is a
CONSTRUCTOR, not more doctrine:** the header must be emitted by whatever composes dispatch
prompts (the orchestrator's dispatch path / a `plan-phase-builder` prompt template), so that
sending it is the default rather than an act of recall.
**Why it matters now:** `task_started` is header-authoritative as of today, so an unheadered
dispatch produces NO green chip. That is deliberate (a missing green is not a lie; a false one
is) but it means the cockpit under-reports real work until adoption rises.
**`doctrine/orchestrator-pattern.md` already calls the header MANDATORY** — so this is a
mechanism gap, not a doctrine gap: the only enforcement is a non-blocking WARN, and 4090
ignored WARNs is the measured proof that a WARN is not a mechanism (constitution §10:
"documented enforcement that does not fire is the cardinal harness defect").
**Fix direction:** make the header a dispatch-time requirement with a real block (or have the
dispatching layer inject it automatically from the task it is dispatching, which removes the
human step entirely — preferred, since it cannot be forgotten).
**Filed by:** plan-phase-builder, false-eternal-running upstream fix, 2026-07-30.

## DISPATCH-PROVENANCE-MARKER-SECOND-COLLISION-01 — markers are silently overwritten within the same second

**Severity:** MEDIUM, OPEN. Found while building the ROADMAP-FALSE-ETERNAL-RUNNING-01 fix.
**Finding (PROVEN by executing test):** `scripts/dispatch-provenance.sh`'s marker filenames are
`UNRESOLVED__<YYYYMMDDHHMMSS>.json` — **one-second granularity with no disambiguator**. Three
distinct dispatches emitted inside one second leave **two** files, not three; the third
silently overwrote a sibling. Reproduced deterministically in
`workstreams-emit.sh --self-test` scenario RPL2 (3 real dispatches -> 2 marker files), which is
why RPL2c asserts "the replay pass adds no new markers" rather than an exact count — pinning
the count would couple that assertion to this unrelated bug.
**Impact:** `pl_classify_session`'s spawned-session guard loses evidence for bursty dispatches,
exactly when there is most of it. Aggravated (not caused) by the 200-marker cap.
**Fix direction:** add a uniqueness suffix (pid + counter, or the item_id's short sha) to the
marker filename, the same way `_dispatch_replay_token` already keys on a hash.
**Filed by:** plan-phase-builder, false-eternal-running upstream fix, 2026-07-30.

## PROGRESS-LOG-ID-PLACEHOLDER-STILL-LIVE-CHECK-01 — "<id" ask_id placeholder bug: checked, currently quarantined and NOT growing

**Severity:** informational (re-confirms `PROGRESS-LOG-ID-JSONL-UNACCOUNTED-01` above, checked
fresh per an explicit ask to verify the emitter bug is "still live").
**Finding (PROVEN, 2026-07-30 live check):** `~/.claude/state/progress-logs/unattributed.jsonl`
holds exactly 26 records with the literal `"ask_id":"<id"` fingerprint, ALL `type:"merged"`
(emitted by `auditor.js`'s merge-scan path, not by `task_started`/`task_done`'s emitters), most
recent write 2026-07-29T16:23:30Z — no new occurrence appeared on 2026-07-30 (today) as of this
check. `grep -rl '"<id' ~/.claude/state/progress-logs/*.jsonl` matches only that one file. The
Task-2 writer-side backstop (this same plan) is quarantining occurrences as designed; the legacy
`_id.jsonl` provenance question is the separate, already-tracked, unresolved item above. This bug
is UNRELATED to ROADMAP-FALSE-ETERNAL-RUNNING-01 above (different event type, different emitter)
and does not explain it.
**Action:** none required beyond what `PROGRESS-LOG-ID-JSONL-UNACCOUNTED-01` already tracks.
**Filed by:** plan-phase-builder, false-eternal-running-fix build, 2026-07-30 (investigation
requested alongside the roadmap rollup fix).
- **REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01** — Resolved (CRITICAL, measured 2026-07-30):
  review-record-commit-gate.sh demands a harness-reviewer PASS record before a builder
  subagent may commit — but builder subagents have NO Task/Agent-dispatch tool, so they
  cannot invoke harness-reviewer. The gate's prescribed remedy is UNREACHABLE from the
  layer the gate fires at. Evidence: ~/.claude/state/review-record-gate-overrides.log
  holds 78 override events (68 on 2026-07-29, 10 on 2026-07-30); EVERY one of today's
  ten states the same reason — "no Task/Agent-dispatch tool; cannot invoke
  harness-reviewer". This is a remedy-chain deadlock (ADR 059 D5 class), not agent
  misconduct: the only two exits are "never commit" or "override". It is also why the
  override exists and why it is used as the normal path.
  FIX DIRECTION (builder aff45ca5 in flight): move the AUTHORITATIVE gate to pre-push,
  where the ORCHESTRATOR — which does have dispatch capability — is the actor, so the
  remedy is reachable from the layer that enforces it. Keep the commit-time gate as
  advisory-only early feedback so builders are informed without being deadlocked.
- **REVIEWED-BYTES-ARE-NOT-COMMITTED-BYTES-01** (HIGH, class confirmed by 2 independent
  occurrences 2026-07-30): a reviewer verifies the WORKING TREE while the INDEX still holds
  the version it rejected — so a commit ships bytes no review ever covered, and the PASS is
  an unfalsifiable claim. Occurrence 1: the cockpit review-surface builder (`MM` on both
  doctrine files + manifest, `AM` on the plan, `??` on the proposal doc; committing would
  have shipped the carrier-parity theatre the reviewer had just removed). Occurrence 2: the
  IF-statement builder (`git show :.../if-statement-check.sh | grep -c perception` = 0 while
  the worktree had the fix; the index held the draft with the `I see ` escape).
  Note only manifest.json is blob-checked by the review gate — doctrine/, plans/ and
  docs/harness-improvements/ are OUTSIDE the surface, so stale staged copies of those ship
  with NO mechanical complaint.
  FIX DIRECTION: (a) any request for review of "staged" work must assert staged-ness
  mechanically (`git diff --stat` empty) IN the request; (b) the reviewer verifies
  index-vs-worktree parity BEFORE issuing a verdict; (c) a review record's blob_shas should
  be taken from the INDEX, and the record capture should refuse when worktree != index.
  This belongs in deterministic-process.md: a gate that verifies bytes other than the ones
  that ship is enforcing nothing.
- **DETERMINISM-PROOF-OBLIGATION-UNBUILT-01** (HIGH, self-caught 2026-07-30):
  `doctrine/deterministic-process.md` shipped with an Enforcement header claiming
  manifest units carry `chokepoint`/`bypass_paths` and that harness-doctor REDs without
  them. MEASURED, all three halves false: 39 blocking units, **0** with `chokepoint`;
  `determinism-chokepoint-declared` has 0 occurrences in harness-doctor.sh;
  `manifest.schema.json` is `additionalProperties: false` and would REJECT both keys.
  Caught by a builder within hours — the file whose thesis is that unbuilt enforcement
  claims are the cardinal defect shipped an unbuilt enforcement claim. Header corrected
  to PATTERN + a named correction rather than silently edited.
  TO CLOSE: (1) schema gains both properties; (2) a real doctor check; (3) backfill the
  blocking units (dated grandfather acceptable, per the review-record precedent);
  only then does the Enforcement line come back.
  **UPDATE 2026-07-30 (harness-reviewer follow-up):** (1) and (2) are DONE — the schema
  defines both fields, and `check_deterministic_process_proof` REDs on a blocking entry
  missing EITHER (tightened from both-missing-only). The doctrine header now states the
  hybrid state instead of the stale "NONE YET", which had itself become an INVERSE
  vaporware claim (asserting the schema "would REJECT both keys" after the same commit
  added them). Also corrected: the unit count was 40, not 39 — `intended-functionality-
  if-statement` was blocking:true with neither field and on no grandfather list, so the
  doctor RED'd from the moment the check landed; it is now backfilled with a real
  chokepoint + 8 enumerated bypasses. (3) REMAINS OPEN: 38 of 40 blocking units still
  carry neither field and are exempted only by the dated grandfather list. This entry
  closes when that list reaches empty. Re-derive, never quote:
  `jq -r '.entries[]|select(.blocking==true)|select((((.chokepoint//"")|length)==0) or (((.bypass_paths//[])|length)==0))|.id' adapters/claude-code/manifest.json | wc -l`
- **REVIEW-COVERAGE-DB-IS-UNGATED-REPO-CONTENT-01** (HIGH, PROVEN 2026-07-30 by
  harness-reviewer against live fixtures, partially closed same day): the coverage
  database `review-record-push-gate.sh` consults (`docs/reviews/records/{index,
  grandfather-manifest}.json`) is unprotected repo content the pushing agent can author
  in the SAME push, and neither `rrg_in_surface` nor `scope-enforcement-gate.sh:188`
  gates that path. Three routes each took the gate from rc=1 to rc=0. CLOSED: a
  self-authored grandfather row (rows are now verified against the manifest's own
  `cutover_ref`), and deleting both coverage files (the bootstrap fail-open is now
  scoped to repos without `adapters/claude-code/manifest.json`). **STILL OPEN:** a
  self-written `{kind:"harness-change-review", verdict:"PASS"}` row in `index.json`
  still covers the pusher's own content — indistinguishable at push time from the
  legitimate `review-runner.sh finalize` flow, which writes exactly that row in exactly
  that push. Detected only post-hoc by the doctor's `review-index-consistency` check,
  which `deterministic-process.md:31-33` names as auditing-instead-of-enforcement.
  TO CLOSE: an independence signal the pushing agent cannot mint — a reviewer-side
  signature over `{path, blob_sha, verdict}`, or a server-side required-status-check.
  Tracked alongside `docs/plans/review-independence.md`.
  CLASS LESSON (the reason this is HIGH and not a one-off): a gate whose verdict depends
  on repo-resident state must treat that state as part of its own trust boundary.
- **REVIEW-SURFACE-OMITS-ITS-OWN-DISPATCHER-01** (HIGH, PROVEN 2026-07-30 while
  fixing harness-reviewer M8): `adapters/claude-code/git-hooks/pre-push` — the
  dispatcher that DECIDES WHETHER the authoritative review gate runs at all — is NOT
  in the review-record trigger surface. `rrg_in_surface` matches `hooks/**/*.sh`,
  `scripts/**/*.sh`, `agents/*.md`, `config/**`, `manifest.json`,
  `settings.json.template`, `rules/**`; `git-hooks/pre-push` matches none of them
  (it is extensionless and under `git-hooks/`, not `hooks/`). PROVEN by sourcing the
  lib and running `rrg_in_surface` over this very commit's changed files: the
  dispatcher came back "not gated" while the five `hooks/*.sh` + `manifest.json`
  files came back in-surface, and the live gate's own block message listed exactly
  those five. So an edit to the dispatcher — including deleting the stage that
  invokes the review gate — reaches master with ZERO review coverage. This is the
  sharpest form of harness-reviewer M8 ("the enforcing bytes are mutable"): M8 is
  about a checkout/stash disarming the gate locally, this is about an unreviewed
  COMMIT disarming it permanently for everyone.
  ALSO NOT IN SURFACE, same root cause: `adapters/claude-code/schemas/
  manifest.schema.json` (governs what every manifest entry may declare, including
  the chokepoint/bypass_paths proof obligation) and `adapters/claude-code/
  doctrine/**` (the doctrine the gates cite as their authority).
  TO CLOSE: extend `rrg_in_surface` to cover `git-hooks/*` and `schemas/*.json` at
  minimum, then re-bootstrap the grandfather manifest so existing content is
  covered. Note the cost is real and should be measured first (the Amendment G
  precedent measured 26 newly in-surface files before landing).
  CLASS LESSON: the trigger surface of a review gate must include every file that
  can change whether that gate runs — enumerate the gate's own carrier chain, not
  just the code it inspects.
  **RESOLVED (mostly) 2026-07-30** — harness-reviewer CRITICAL 3 confirmed this
  finding and rejected the deferral rationale as unmeasured, so the cost was
  measured and four of the five arms landed as Amendment H in `rrg_in_surface`:
  `git-hooks/*` (5 files), `schemas/*.json` (11), `install.sh` + `sync.sh` (2), and
  non-`.sh` code members of `hooks/`+`scripts/` (10). Surface 283 → 311 tracked
  files (+28, +9.9%), measured identically on `/bin/bash` 3.2.57 and
  `/opt/homebrew/bin/bash` 5.3.15. Pure DELETION of an in-surface file also blocks
  now (`--diff-filter=ACMR` excluded `D`, so `git rm` of a gate was a rc=0 no-op);
  measured FP cost of that arm: 8 of 1763 commits on master (0.45%) delete an
  in-surface file. NOTE the reviewer's suggested "cover executable non-`.sh`
  members" rule was measured and REJECTED: all 13 tracked non-`.sh` files under
  `hooks/`+`scripts/` are mode 100644, so a mode-bit rule would have matched ZERO
  files and shipped as theatre; the landed rule is extension-based.
  **FULLY RESOLVED 2026-07-30 (round 3)** — harness-reviewer returned a second
  REJECT showing the round-2 closure was partial in two independent ways, both
  now closed and both regression- and mutation-tested:
  (1) **The outcome had four verbs, and only two were closed.** "The enforcing
  file is gone from its enforcing path" is reachable by edit (`M`), `git rm`
  (`D`), `git mv` (`R100 <old> <new>` — `--diff-filter=ACMR` emits ONLY the
  destination, `--diff-filter=D` emits NOTHING) and typechange (`T` — excluded by
  BOTH). PROVEN against a real bare remote with the live gate as the pre-push
  hook: `git mv adapters/claude-code/git-hooks/pre-push docs/pre-push` pushed
  **rc=0 with ZERO gate bytes and the path GONE from the remote**, and a
  regular-file→symlink typechange pushed rc=0 leaving the remote carrying mode
  120000. Closed by `--diff-filter=ACMRT` + a `--diff-filter=D --no-renames`
  pass. Re-measured FP bill independently over all 1763 master commits: rename
  sources **+38 files / +7 commits (0.40%)** — note this is HIGHER than the
  0.34% the review cited, which counted only renames *out of* the surface and
  omitted one rename *within* it (`rules/conversation-tree-state.md` →
  `rules/workstreams-state.md`, `e272c3e`); typechanges 0/0, free. Still cheaper
  than the 0.45% deletion arm already accepted.
  (2) **The extension-based rule was itself the hand-written list the header
  disclaimed.** `hooks/`, `scripts/` and `schemas/` were extension allowlists
  while the lib header claimed the surface was "derived from the gate's CARRIER
  CHAIN, not from a hand-written path list". Today's tree was fully covered, so
  there was no present-day hole — the defect was the absence of the very
  drift-resistance the claim advertised (`hooks/lib/evil.mjs`, `.cjs`,
  `hooks/evil.rb`, `.pl`, `.lua`, `schemas/x.yaml` each probed NOT-COVERED). All
  four carrier trees are now UNFILTERED minus an exact-path exemption list of
  three known non-code members; MEASURED identical 311-file surface either way,
  so zero present-day FP cost. The earlier "the landed rule is extension-based"
  sentence above is therefore SUPERSEDED — the executable-bit rejection stands,
  its replacement did not.
  CLASS LESSON (extended): every gate deriving a subject set from `git diff` must
  enumerate by the **codes through which its subject can change or LEAVE the
  surface**, never by a hand-listed set of verbs; and every new self-test carries
  a `git mv` case and a typechange case beside its `git rm` case.
  **STILL DEFERRED — `adapters/claude-code/doctrine/**`**, with its cost now
  measured rather than asserted: **89 tracked files** (`git ls-files
  'adapters/claude-code/doctrine/*' | wc -l`), a +31% surface expansion on its own
  and larger than all four landed arms combined. Doctrine is prose that changes far
  more often than the code enforcing it, so the merge-friction bill is real and
  recurring — this is the one arm where deferral survives measurement. TO CLOSE:
  decide whether doctrine changes warrant a review record at all (they are
  authority, not enforcement bytes — a doctrine edit cannot by itself disarm a
  gate), and if so re-bootstrap the grandfather manifest over all 89 first.
- **DOCTOR-BUDGET-BLOCKING-GATES-RED-15-OF-14-01** (MEDIUM, PROVEN pre-existing
  2026-07-30): `harness-doctor.sh --quick` REDs `budget-blocking-gates: blocking
  session-event units: 15/14`. Reproduced identically against HEAD's manifest with the
  same full adapter tree, so it predates and is unrelated to the deterministic-process
  work. Not fixed there to avoid bundling an unrelated demotion decision into a review-
  findings commit. TO CLOSE: demote one unit via `scripts/gate-demotion.sh` or
  consolidate per ADR 059 D7 — an explicit budget decision, not a mechanical fix.
- **REVIEW-RECORD-GATE-STAGE-AND-COMMIT-FAIL-OPEN-01** (CRITICAL, PROVEN 2026-07-30 by a
  builder that self-reported it, orchestrator-confirmed by code read):
  `review-record-commit-gate.sh:427-428` reads the index at PreToolUse:
  `staged="$(git -C "$repo_root" diff --cached --name-only ...)"` then
  `[[ -n "$staged" ]] || return 0   # exemption 1: nothing staged`.
  For the command `git add -A && git commit ...` the `git add` HAS NOT RUN YET at
  PreToolUse, so the index is empty, `$staged` is empty, and the gate SILENTLY ALLOWS
  (exit 0, zero output). Builder's executed matrix:
    staged   + `git commit -m x`                     -> exit 2 (BLOCKED)
    staged   + `git add -A && ... && git commit -F`  -> exit 2 (BLOCKED)
    UNSTAGED + `git add -A && ... && git commit -F`  -> exit 0, SILENT ALLOW
  `git add -A && git commit` is the single most common commit idiom; the builder reached
  for it unprompted. No bypass env is needed or set — this is invisible in the override
  audit log, so the 78 logged overrides UNDERSTATE unreviewed landings.
  WORSE: the gate's own self-test Scenario 4 ASSERTS the hole as correct behaviour
  (`[[ "$rc" == "0" ]] && pass "no staged files -> allowed"`), so the suite defends it.
  This is deterministic-process rule 1 exactly: the gate is at a layer where it cannot
  see what will actually be committed. At pre-push the commits already exist, so the
  class cannot occur — further evidence for moving authority to the funnel.
  TO CLOSE: (a) the gate must evaluate what the COMMAND WILL STAGE (parse `git add`
  args / use the post-add tree), not the pre-command index; (b) Scenario 4 must
  distinguish "genuinely empty commit" from "empty index because add has not run yet";
  (c) AUDIT what landed via this route historically.
  **RESOLVED** (builder aff45ca5, same commit as this entry's update): hooks/
  review-record-push-gate.sh landed as the authoritative pre-push carrier (wired into
  git-hooks/pre-push); review-record-commit-gate.sh demoted to blocking:false
  (advisory-only, REVIEW_RECORD_GATE_OVERRIDE removed entirely — nothing left to
  waive). Self-test 1b on the commit gate proves a builder with no override set makes
  forward progress; Scenarios 1-13b on the push gate prove the same content is still
  refused at push time. harness-reviewer PASS obtained on the full diff (Critical/Major
  findings fixed in the same commit: a range-diff fail-open at push-gate.sh, a missing
  bypass_paths enumeration entry for self-issued override markers, and stale doctrine/
  review-before-deploy.md claims that the commit gate "IS the enforcement").

- **PRE-PUSH-SCAN-RANGE-DIFF-FAIL-OPEN-01** (Major, found 2026-07-30 by harness-reviewer
  during the above review, spawned as task_28b9098f): hooks/pre-push-scan.sh (the
  credential/secret scanner) line ~218 scores a failed `git diff --name-only "$range"`
  (e.g. an unresolvable `remote_sha`, PROVEN reachable on both a plain push and a
  `--force` push) as "zero files changed" via `2>/dev/null || echo ""`, silently
  skipping the scan instead of falling back to a wider range. Same bug class already
  fixed in hooks/review-record-push-gate.sh's `_rrpg_main` (see the `diff_rc` handling
  and self-test Scenario 13b) — apply the identical empty-tree fallback here. Flagged
  as a spawned task rather than fixed in-line to keep this commit's diff reviewable.

- **RQ-AUTO-ENQUEUE-NOT-RANGE-AWARE-01** (Minor, found 2026-07-30 by harness-reviewer):
  hooks/lib/review-queue-auto-enqueue-lib.sh's rq_auto_enqueue_uncovered reads `git diff
  --cached` (the INDEX) — correct for review-record-commit-gate.sh's commit-time call,
  but a hypothetical push-time caller would find the index normally equal to HEAD and the
  call would be wired-but-permanently-inert. review-record-push-gate.sh deliberately does
  NOT call it (see the gate's own comment at its RI1b section) rather than wire an inert
  step. A RANGE-aware entry point (taking an explicit path+blob-sha list rather than
  re-deriving from the index) would let the push gate auto-enqueue independent review for
  content it blocks or overrides too — not built in this pass.

## NL-ISSUES-TRIAGE-20260731 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 109 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 2d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).
- **LEARNING-LEDGER-CAPTURES-MACHINE-NOISE-AS-OPERATOR-VERBATIM-01** (HIGH, MEASURED
  2026-07-31): the operator-defect learning loop built today is being poisoned at the source.
  Of 25 nl-issue rows tagged `[src:operator-verbatim]`, **17 are SYSTEM `<task-notification>`
  blocks, not the operator** — only 8 carry the operator's real words. The PROBLEM-CAPTURE
  vocabulary in workstreams-read.sh fires on the injected task-notification text (which
  contains complaint-shaped words from agent reports) as if the operator had typed it.
  CONSEQUENCE: the ledger whose entire purpose is capturing operator-reported defects — the
  thing that is supposed to make the harness learn without the operator having to shout —
  is 68% machine noise. Its class-rollup escalation therefore escalates on agent chatter.
  EXACT SAME CLASS as the Requests-tab defect fixed today (machine output displacing the
  operator's own words; there the 401 error string overwrote a real request title).
  FIX: PROBLEM-CAPTURE must exclude injected system blocks — a turn whose text begins with
  `[SYSTEM NOTIFICATION` or contains a `<task-notification>` element is NOT operator input,
  by the same rule the session prompt states outright. Add a RED fixture per shape.
- **SPAWN-TASK-CHIPS-ARE-A-NON-DETERMINISTIC-HANDOFF-01** (HIGH, operator 2026-07-31:
  "What happened to you agreeing not to spawn sessions through chips? ... it probably sat
  there for hours before I saw it"): a spawn_task chip reaches the operator ONLY if they
  happen to look — deterministic-process.md rule 3 (a step nothing invokes is not part of
  the process). task_28b9098f sat unseen for hours. Root cause of THIS instance: the
  constraint was never carried into subagent dispatch briefs, so a builder spawned it.
  FIX: (a) every dispatch brief carries "do not spawn_task chips; file to docs/backlog.md
  or needs-you.sh instead"; (b) anything genuinely needing the operator goes to NEEDS-YOU.md
  AND is stated in chat the same turn — the durable ledger is the deterministic surface,
  the chip is not.

## SURFACE-PREDICATE-NARROWER-THAN-DELIVERY-IDENTITY-01 — the same class, caught twice in one day

**Severity:** CRITICAL, OPEN (fix in flight)
**Confidence:** PROVEN — reproduced end-to-end against a real bare remote with the gate
installed as the actual pre-push hook, by an independent harness-reviewer.

**The class.** A harness predicate decides membership by comparing a path STRING under an
equivalence relation NARROWER than the one the delivery layer actually applies. The predicate
answers truthfully about the string it was given, and the wrong thing lands anyway.

**Instance 1 (closed, round 4).** `rrg_in_surface` was asked about git's C-quoted *rendering*
of a path rather than the path. `hooks/pré-push-gate.sh` classified out-of-surface → rc=0,
silent, unreviewed hook landed. Closed in 802a937.

**Instance 2 (OPEN, found in round 5).** The same predicate matches tree prefixes
case-SENSITIVELY (`case "$rel" in hooks/*)`, review-record-gate-lib.sh:138-211) while the
surface it protects is realised on a case-INSENSITIVE filesystem. PROVEN:
`git update-index --add --cacheinfo 100755,<blob>,adapters/claude-code/Hooks/injected.sh`
(capital H) + commit + push → **rc=0, gate SILENT, LANDS on the remote**, and a later clone
materialises it at `adapters/claude-code/hooks/injected.sh`, inside the real carrier directory
alongside the genuine hooks. Same silent rc=0 for `Git-Hooks/pre-push`, `SCRIPTS/evil.sh`,
`adapters/Claude-Code/hooks/evil.sh`, `Manifest.json`.
Direction matters: the CLOBBER direction is NOT exploitable (0 of 311 in-surface canonical
paths contain an uppercase letter, so the all-lowercase real path sorts last in the index and
wins the checkout race). The exploitable direction is INJECTION of a new path with no
lowercase competitor. `review-record-gate-lib.sh:161` currently claims "a new file of any kind
under these trees is IN surface by default" — false for case variants, exactly as it was false
for C-quoted paths before round 4.

**Still untested, same class:** Unicode NFC/NFD normalisation on APFS; trailing dot/space
stripping on Windows checkouts.

**The generalization (this is the point of the row).** Every predicate deciding membership
from a path string must normalise on EVERY equivalence the delivery layer collapses —
encoding (closed), case (in flight), Unicode normalisation (untested), Windows trailing
characters (untested). The round-4 rule "disable quoting AND use NUL separation" is
insufficient and must be extended with "AND normalise to the delivery filesystem's equivalence
class before the predicate."
**Sweep:** `rg -n 'case "\$(rel|full|path|f)" in' adapters/claude-code/hooks/lib/ adapters/claude-code/hooks/ adapters/claude-code/scripts/ | rg -v 'tr .A-Z..a-z.|casefold|nocasematch'`

## RUNTIME-VERIFICATION-EXECUTES-MARKDOWN-AT-SESSION-END-01 — arbitrary write + exfil path

**Severity:** CRITICAL, OPEN (fix in flight). **Current exposure: NONE** — the gate is not
installed (live `~/.claude/hooks/runtime-verification-gate.sh` absent; live dispatcher still
lists 3 member gates). It becomes live if `worktree-wf_795d2726-dc4-5` reaches master.
**Confidence:** PROVEN by execution, by an independent harness-reviewer.

The rewired Stop gate executes `curl` command lines harvested from MARKDOWN at every session
end, unattended. A fixture whose only evidence line was
`Runtime verification: curl -o <path> file:///etc/hosts` caused the file to be created (213
bytes of /etc/hosts); a second run **overwrote an executable hook script** — i.e. next-session
code execution. The only filter is a metacharacter regex
(`runtime-verification-executor.sh:413`); there is NO curl-flag filtering, so `-o` (arbitrary
write), `-T` (upload/exfiltrate any readable file) and `-K` (arbitrary curl config) all pass.

**Two further delivery paths, both PROVEN:** (i) a CLEAN working tree with someone else's
branch checked out executes THEIR committed curl lines via the base..HEAD diff; (ii) an
UNTRACKED `.md` is read whole-file (`:170`), so a postmortem or review that merely QUOTES an
evidence line executes it.

**The boundary this violates, stated positively:** verify by READING files, never by RUNNING
content. The gate's own header at `:44-49` ALREADY CLAIMS it does this — the claim is true for
three branches and false for `curl` and `sql`.

**Do not resolve this by retiring the gate.** Operator directive 2026-07-31, verbatim: "Are
you seriously suggesting that the solution is to simply give in to the theater? Rewire it!
Make it work!" The fix is to classify curl/sql UNVERIFIABLE like `command`/`bash`, which also
collapses the companion defect below.

**Companion — fp_expectation measured on a filtered corpus.** The entry claims "Near-zero on
added lines, by construction and by measurement," but the measurement covered only "the 1344
NON-CURL Runtime verification: lines" — it excluded the single format with the highest FP
rate. Re-measured over the 25 real curl/sql lines in docs/: **16 failures / 9 passes = 64%
failure on real, largely TRUE evidence.** A corpus filtered to remove the failing class is not
a measurement. Class: `fp-measurement-excludes-the-failing-population`.

**Companion — a stale date evades the §10 evidence bar.** `manifest.json` `runtime-verification`
carries `added_after: "2026-04"` while `harness-doctor.sh:2354` does
`if (addedAfter < "2026-07") continue;`, so the doctor SKIPS the new-gate bar entirely and never
validates golden_scenario / fp_expectation / retirement_condition — on an enforcing artifact
written 2026-07-31 that has never fired. `harness-doctor.sh:2288-2295` says grandfathering must
go via `PRE_BAR_GRANDFATHERED`, "never by under-dating." Generalization: `added_after` tracks
the landing month of the ENFORCING ARTIFACT, not the unit's inception.

## INBOX-EXPLAINS-THE-SYSTEM-NOT-THE-DECISION-01 — the card answers the wrong question

**Severity:** HIGH, PARTIALLY FIXED 2026-07-31 (client ordering landed; the producer
half is untouched). **Source:** operator, verbatim: "the info that's presented to me in
the Inbox doesn't do a fantastic job of providing context to help me understand the
issue and determine what to do about it."

**LANDED this round (client, `inbox.js`):** actions hoisted into a "Run this" block
above the prose; labelled commands (`STEP 3: powershell ...`) now fence with their own
Copy button carrying the command ONLY; the 5-line cap no longer drops action lines; the
trade-offs table and My-pick now render ABOVE the background instead of below it; the
30s tick no longer re-renders when nothing changed. Live-verified: 2 ticks, 0 DOM
mutations, scroll held at 900.

**STILL OPEN — the producer half, which is where the real defect lives.** The card
faithfully renders what `needs-you.sh` was given, and what it is given is an explanation
of the SYSTEM rather than the material for a DECISION. Concretely, on the operator's own
live item NY-1785425479-0d4d:

1. **Process noise occupies the most prominent text.** The title ends "(supersedes
   retracted NY-1785394095-d8ec; corrected after a wrong diagnosis)". A retracted id and
   the author's own wrong turn are provenance, not decision content, and they sit in the
   headline. FIX: the cold-reader lint should REJECT retracted-id references and
   self-referential correction notes in `--text` titles; provenance belongs in the
   collapsed "Raw verbatim + session lineage" block that already exists.
2. **Double labelling.** Renders as "Decision needed: Action needed: register the ...".
   The server strips ONE redundant prefix; the producer wrote two.
3. **No "why does this need ME" field.** This is the single highest-value missing datum —
   the operator's first question is always "can't you just do it?". One item answers it
   well (the settings.json row names the grant-local-edit bar); the others do not. FIX:
   make it a REQUIRED field, lint-enforced, alongside the existing five.
4. **No effort estimate.** "three commands" appears only inside My-pick prose. FIX:
   required field, rendered as a chip next to the age.
5. **No currency signal.** The item is 14h old and nothing says whether it is still true.
   FIX: re-derive at render and show "still current as of <t>", or flag it stale.
6. **Background explains architecture, not consequence.** "coord-sync pushes each
   machine's live session state ... every 60s" is how the system works; what the operator
   needs is what they gain and what they lose. The options table already carries that and
   is now rendered first — the background should be SHORTER, not merely later.

**The generalization:** an inbox card is a decision surface, not a status report. Every
field must earn its place by changing what the operator would DO. The producer's lint
currently checks that fields are PRESENT and cold-readable; it does not check that they
are DECISION-RELEVANT, which is why a structurally-perfect card can still be unusable.

## NL-ISSUES-TRIAGE-20260801 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 111 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 23d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NL-ISSUES-TRIAGE-20260802 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 7 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 0d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## CI-REQUIRED-CHECK-PR-ONLY-01 — the required check IS real; the defects are red-since-07-29 checks, an admin bypass, and a push/PR trigger asymmetry

**Severity:** HIGH, OPEN. **Confidence:** PROVEN by protection API + PR #106 check rollup +
run history + local reproduction, 2026-08-02, work account `MishaPT`.

**CORRECTS an unmerged row.** Commit `10b4e5a` on branch `wip/harness-hardening-2026-07-29`
(not on master) filed `CI-REQUIRED-CHECK-NAMES-NOTHING-01`, whose headline — "no workflow
produces a check named `validate`" — is **FALSE**. When that branch merges, its row must be
replaced by this one. That commit was itself a retraction of an earlier false claim ("you have
no CI"); this is the second false headline in the same investigation, and the cause of both was
reasoning from workflow-level `name:` fields without reading the produced check names.

**REFUTED — claim (a).** `.github/workflows/pr-template-check.yml` declares `jobs: validate:`
with **no** `name:` key. GitHub derives a check-run name from the job's `name:` when present and
falls back to the **job ID** otherwise, so the produced check name is literally `validate` —
exactly matching `required_status_checks.contexts: ["validate"]`. Decisive evidence, not
inference: `gh pr view 106 --json statusCheckRollup` returns
`{"name":"validate","workflowName":"PR Template Check","conclusion":"FAILURE"}`.
The gate is real, it reports, and it is currently RED on #106.

**CONFIRMED — claim (b).** `enforce_admins.enabled: false`. Owner pushes skip protection.

**CONFIRMED but understated — claim (c).** Not "three consecutive pushes": `Evals` and
`Server-side enforcement` have failed on **12 consecutive master pushes**, last green
2026-07-29T23:09Z. `Secret scan CI backstop` failed once more (2026-08-01T13:48Z). Both
failures reproduce locally:
- `Evals` → `evals/golden/rules-index-coverage.sh` exits 1: 10 doctrine compacts lack an
  `INDEX.md` row, 6 exceed the 3000-byte cap. **This is a regression of an already-fixed
  defect** — backlog v69 (2026-07-17) records "5 over-cap doctrine compacts trimmed, Evals CI
  GREEN again". Fix: `bash adapters/claude-code/scripts/manifest-check.sh --gen-index`.
- `Server-side enforcement` → `plan-edit-validator.sh --self-test` = 15 passed / 4 failed
  (F16-F19). Root cause is a shell bug, not a policy failure: `plan-edit-validator.sh:1467`
  and `:1535` run `stat -c %Y "$f"`, which on a non-GNU `stat` emits a multi-line `stat -f`
  style block; that block is then fed to `age=$((now - mtime))`, producing
  `syntax error in expression (error token is ": "/tmp/...")`. The three sibling jobs
  (credential-scan, harness-hygiene, no-test-skip) all pass.

**PARTLY REFUTED — claim (d).** The premise "all six workflows trigger on `push:[master]` +
`pull_request`" is wrong for two of six: `pr-template-check.yml` is `pull_request` **only**,
and `synthetic-runner.yml` is weekly `schedule` + `pull_request` (paths-filtered). The
*conclusion* stands and is confirmed: **no workflow has a `push:` trigger for any non-master
branch**, so branch pushes run zero checks. `gh run list --limit 100` shows exactly one
non-master branch with runs — `claude/busy-kare-3dba65`, and those are `pull_request`-triggered
(PR #106), not push-triggered. The "13 branches on 07-31" count is also low: the repo activity
API shows **20+ `branch_creation` events on 2026-07-31 alone**, plus non-master pushes to
`wip/harness-hardening-2026-07-29`, `ws-ui-server-stable`, and three `harness/active-sessions/*`.

**THE COUPLING TRAP — do not flip `enforce_admins` first.** Because `validate` is produced only
by a `pull_request`-triggered workflow, a **push** to master can never produce it. Today that is
harmless (`enforce_admins:false`). Setting `enforce_admins: true` while `validate` remains the
required context would make direct pushes to master permanently unmergeable — the owner's normal
push-to-master workflow would hard-stop with "Required status check 'validate' is expected".
HYPOTHESIZED (standard GitHub protection semantics; not executed here — refuter: flip it and a
direct master push still succeeds). **Fix the context list BEFORE touching `enforce_admins`.**

**PR #106 is blocked by neither billing nor a phantom check.** `mergeable: MERGEABLE`,
`mergeStateStatus: BEHIND`, `rebaseable: false`. `strict: true` (require branches up to date)
is the blocker; the branch is behind master. Its `validate` check is additionally FAILURE, so
the branch also needs a template-compliant PR body. Actions billing is not implicated: runs
executed normally through 2026-08-02T00:41Z and `actions/permissions` returns `enabled:true`.

**GENERALIZATION (retained from `10b4e5a`, and now proven both ways).** A required step whose
IDENTIFIER does not match the thing that PRODUCES it is indistinguishable, in every inventory
and dashboard, from a step that works. The converse is the trap this investigation actually hit:
an identifier that LOOKS orphaned because the producer's name is implicit — GitHub's job-ID
fallback — is indistinguishable from a genuine orphan. **Verify against the produced name, never
the declared name, and never the absence of a declaration.**

**Sweep run 2026-08-02 (identifier vs producer), results:**
- `required_status_checks` — 1 context (`validate`), producer found. CLEAN.
- manifest `entries[].hooks[]` — 0 missing of 127 references. CLEAN.
- manifest `entries[].doctrine_file` — 0 missing of 106 references. CLEAN.
- hook scripts on disk unreferenced by manifest — 0 of 112. CLEAN.
- `settings.json.template` → disk — 0 missing of 56 referenced scripts. CLEAN.
- manifest `wired_template:true` → template — 1 of 48 absent
  (`lib/sessionstart-singleflight.sh`); **not a defect**, it is `source`d by
  `session-start-auto-install.sh:595`, not wired as its own hook.
- manifest `selftest:true` → `--self-test` branch present — **1 of 96 fails**:
  `adapters/claude-code/hooks/runtime-verification-reviewer.sh` has no `--self-test` handler,
  and its only invoker is `adapters/claude-code/attic/pre-stop-verifier.sh:587` (retired to
  attic). The manifest asserts a capability the artifact does not have, for a script nothing
  live calls. **This is the one true in-repo instance of the class.** Fix: drop `selftest` from
  the `runtime-verification` entry's second hook, or retire the script alongside its caller.
- **Sweep-method caveat, filed because it is the same class:** the first three runs of this
  sweep reported 127/127 and 106/106 "MISSING" — a total false positive. Cause: `jq` on this
  machine writes **CRLF** when redirected to a file, so `read` produced `foo.sh\r` and every
  `[ -e ]` test failed. Any sweep that shells `jq > file` on Windows must `tr -d '\r'`.
  Consistent with the standing `od -c` lesson (NL-FINDING-038).

**FIX, ordered (each independent; commands in the 2026-08-02 session report):**
1. Regenerate the doctrine index + trim over-cap compacts → re-greens `Evals`.
2. Fix the `stat -c %Y` arithmetic in `plan-edit-validator.sh:1467,1535` → re-greens
   `Server-side enforcement`.
   **RESOLVED 2026-08-03 (gated-pipeline-master-2026-08 Task 8 triage), corrected diagnosis:**
   the fault is NOT in production lines 1467/1535 (those `stat -c %Y ... || echo 0` call sites
   are fine — GNU `stat -c` works correctly on both this machine and the Linux CI runner). The
   actual break is in the self-test's OWN `F16_BINSHIM` fixture (around line 1118): a `stat`
   shim built for the F16-F19 scenarios unconditionally translated `-c %Y` to
   `/usr/bin/stat -f %m`, assuming `/usr/bin/stat` is BSD's. On GNU coreutils (this Windows/
   MSYS2 checkout, and any GNU/Linux CI runner) `-f` means `--file-system` (dump filesystem
   info, wrong shape entirely, not an error) — reproduced directly:
   `/usr/bin/stat -f %m <file>` prints a multi-line `File: ... Block size: ... Inodes: ...`
   block, which `age=$((now - mtime))` then chokes on exactly as this entry describes. Fixed by
   trying the GNU form for real first (`/usr/bin/stat -c %Y "$@" 2>/dev/null || /usr/bin/stat -f %m "$@"`)
   — verified `plan-edit-validator.sh --self-test` now 24/24 PASS (was 20/4). This should also
   re-green CI's `Server-side enforcement` job (same self-test, same shim, same GNU runner).
3. Only then widen `required_status_checks.contexts` to include push-produced job names
   (`Bash hooks --self-test`, `All-checks summary`, `Golden behavioral tests`,
   `Credential + hygiene-denylist scan (defense-in-depth backstop)`).
4. Only after (3) is green, decide `enforce_admins` — it converts push-to-master into a
   PR-only workflow.
5. Branch-push triggers are a COST decision, not a correctness one: adding `push:` for all
   branches multiplies Actions minutes by the ~20-branches/day worktree churn. Recommend
   `push: branches-ignore: [worktree-*, harness/active-sessions/*]` if adopted at all.

## SELFTEST-SWEEP-NONODE-SHIM-WINDOWS-01 — FIXED 2026-08-04 (shim launcher only; see
CLAIM-HONESTY-JQ-NODE-DIVERGENCE-01 below for a genuine bug this fix unmasked) — harness-
doctor.sh's own P-14 jq-parity self-test could not exercise its nonode fallback on Windows/
MSYS2 (added 2026-08-03, gated-pipeline-master-2026-08 Task 8 doctor triage; label:
`harness-gap`, `priority:medium`).

**Fix landed (gated-pipeline-master-2026-08 Task 8 continuation, 2026-08-04):** per this entry's
own proposed direction — `_nonode_path()` (harness-doctor.sh, self-test section) no longer
symlinks `bash` into the shim, and `_run_quick_nonode()` resolves the real interpreter via
`${BASH:-$(command -v bash)}` BEFORE the `PATH="$shim"` override, so the grandchild's own
command-name lookup never touches the shim's PATH. **Re-verified: 4 of the 5 previously-crashing
scenarios now PASS** (`dpp-jq-parity-red`, `dpp-jq-parity-grandfather`, `ngeb-jq-parity-red`,
`budget-chains-jq-parity-red`) — `harness-doctor.sh --self-test` went from 186 passed/5 failed to
190 passed/1 failed. The 5th (`claim-honesty-jq-parity-red`) no longer crashes either, but now
fails with a DIFFERENT, genuine finding — see the new entry below; the "independently confirmed
the doctor's jq branches themselves are fine... no divergence found... by inspection" claim
originally in this entry is WRONG for `claim-honesty` specifically (inspection missed it because
the shim crash had never let the jq branch actually run before now).

## CLAIM-HONESTY-JQ-NODE-DIVERGENCE-01 — `extract_manifest_gates`'s jq fallback and node branch
produce different output for the same manifest fixture (added 2026-08-04, gated-pipeline-
master-2026-08 Task 8 doctor triage continuation, exposed by fixing SELFTEST-SWEEP-NONODE-SHIM-
WINDOWS-01 above; label: `harness-gap`, `priority:medium`).

**Symptom, PROVEN (`harness-doctor.sh --self-test`, scenario `claim-honesty-jq-parity-red`):**
against the self-test's `wired-gate` fixture, the node branch of `extract_manifest_gates`
(harness-doctor.sh:656-664) emits ONE claim-honesty RED (`manifest gate 'pending-gate' has
wired_template false and no honest_status`); the jq branch (harness-doctor.sh:665-672) emits
THAT SAME RED plus a SECOND one the node branch never produces: `manifest gate 'wired-gate'
claims wired_template true but hook 'wired-gate.sh' does not appear in live settings.json — run
install`. The two branches are supposed to be byte-identical (`_assert_node_jq_parity`'s whole
purpose, harness-doctor.sh ~4410-4420) — this is a real divergence, not a fixture artifact (the
same fixture drives both branches in the same self-test run).

**Not root-caused here (out of this task's sweep-layer scope):** HYPOTHESIZED (refuter: diff the
raw `GATE`/`GH` stream lines the two branches emit for the `wired-gate` entry, byte for byte,
against harness-doctor.sh:656-672's two implementations) — the jq form's boolean/array handling
of `wired_template`/`hooks` for this entry shape differs from the node form's, causing check_claim_
honesty's live-settings.json cross-check (harness-doctor.sh:710-727) to fire on the jq branch
only. Needs a side-by-side stream dump to confirm before touching either jq or node expression.

**Symptom:** `harness-doctor.sh --self-test` reports 5 failing scenarios (`dpp-jq-parity-red`,
`dpp-jq-parity-grandfather`, `ngeb-jq-parity-red`, `claim-honesty-jq-parity-red`,
`budget-chains-jq-parity-red`) — exactly the P-14 finding
(`docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md`). Each fails with "jq branch produced
NOTHING on a fixture that must report."

**Root cause, PROVEN, and it is NOT a doctor logic defect:** `_nonode_path()` (harness-doctor.sh
~line 4139) builds a PATH-shim directory of symlinks to every tool the doctor needs except
`node`, then `_run_quick_nonode` does `PATH="$shim" bash "$SELF_TEST_HOOK" --quick ...`. Because
a bash prefix-assignment affects lookup of the command itself, this re-execs the SYMLINKED
`bash` inside the shim. On Windows/MSYS2, `bash.exe` needs companion DLLs sitting next to the
real binary — a bare symlink to the exe (no DLLs alongside it) fails to load at all. Reproduced
directly: `PATH=<shim-dir> bash -c 'true'` → `error while loading shared libraries: ?: cannot
open shared object file`. The child crashes before the doctor script (or the check being tested)
ever runs, so grepping the check-id out of its (empty) output correctly reports "produced
NOTHING" — the symptom is real, the cause is the shim's own launcher, not the checks'
`node`/`jq` branching.

**Independent confirmation the doctor's jq branches themselves are fine:** ran the real jq
expressions standalone against live/fixture data outside the shim — e.g.
`jq -r --arg ev Stop '[(.hooks[$ev] // [])[] | (.hooks // []) | length] | add // 0'
~/.claude/settings.json` → `9`, exactly matching the live `budget-chains` RED count. No
divergence found in any of the four checks' jq expressions by inspection either (mirrors the
node branch logic line for line).

**Fix (not done here — self-test-harness portability work, its own scoped task, same family as
the existing macOS-portability program):** `_nonode_path()` needs a Windows-safe way to hide
`node` from a child bash WITHOUT symlinking `bash` itself — e.g. don't put `bash` in the shim at
all (let the child inherit the real, already-loaded interpreter via `$BASH`/`command -v bash`
resolved BEFORE the PATH override, only restricting PATH for the grandchild `node`/`jq` lookups
the script performs internally) or copy (not symlink) the real bash + its DLL directory into the
shim. Until fixed, this 5-scenario failure is expected and reproducible on any Windows/MSYS2
checkout; it does not indicate the doctor's non-node fallback is broken in production (Linux/
macOS runners, real GNU/BSD `bash` resolves fine from a symlink — no DLL sidecar dependency).

## MODEL-PIN-GATE-SELFTEST-NONHERMETIC-01 — model-pin-gate.sh's self-test intermittently reads
live tier-exhaustion state instead of a fixed fixture (added 2026-08-03, gated-pipeline-master-
2026-08 Task 8 doctor triage; label: `harness-gap`, `priority:low`).

**Symptom:** `harness-doctor.sh --full`'s selftest-sweep (check 8) reported
`model-pin-gate.sh --self-test exited 1: model-pin-gate self-test: 15 passed, 2 failed`. Running
`bash adapters/claude-code/hooks/model-pin-gate.sh --self-test` directly, ~15 minutes later, gave
**17 passed, 0 failed** — full GREEN, same commit, same file, no edits in between.

**Diagnosis, HYPOTHESIZED (refuter: instrument the two "tier exhausted" scenarios to print the
tier-state value they read at the moment of failure; if it is genuinely stable across both runs,
this diagnosis is wrong):** the two scenario names most likely to be timing-sensitive are
`pinned agent + tier exhausted → BLOCK naming fallback` and
`explicit model:fable + fable exhausted → BLOCK naming fallback` — both PASSED in my direct
run, and the sweep's own child ran under `nl_run_bounded` + `NL_SELFTEST_SWEEP=1` with a
~15-20 minute gap in wall-clock, real machine tier-exhaustion state, from my run. A self-test
whose outcome depends on real model-tier exhaustion (rather than an injected/mocked tier state)
is non-hermetic by construction — it will flake whenever it happens to run near a tier
boundary. Not chased further (would require reading model-pin-gate.sh's fixture-injection path
in depth); flagged so a future pass hermeticizes the tier-state input for these two scenarios
rather than reading `adapters/claude-code/config/model-policy.json`'s live state.

## SELFTEST-SWEEP-NOT-STALENESS-2026-08-04 — six selftest-sweep REDs are NOT explained by
live-vs-repo staleness, contra this task's own working hypothesis (added 2026-08-04,
gated-pipeline-master-2026-08 Task 8 doctor triage continuation; label: `harness-gap`,
`priority:low`).

**Context:** this session's dispatch hypothesized that most of the 14 selftest-sweep REDs named
in the 2026-08-03 pass (`plan-reviewer.sh`, `scope-enforcement-gate-body.sh`,
`session-start-digest.sh`, `session-start-auto-install.sh`, `concurrent-ownership-gate-body.sh`,
`review-record-commit-gate.sh`, `model-pin-gate.sh`, `admission-lib.sh`, `git-command-parse.sh`,
`self-sync-guard.sh`) share dispatch-chain-gate.sh's PROVEN root cause: the sweep runs the LIVE
mirror copy (`~/.claude/hooks/...`), which lags an in-flight/unmerged branch's repo copy.
`harness-doctor.sh`'s `check_selftest_sweep` was fixed this session (see the T8 commit) to
detect this via `cmp -s` and downgrade a genuinely-diverged failure from RED to a disclosed WARN.

**PROVEN by direct `cmp` on this checkout, same session:** `dispatch-chain-gate.sh` (182 live
lines vs 1121 repo lines) and `review-record-push-gate.sh` (2096 vs 2774) ARE explained by
staleness — confirmed massively diverged. But six of the ten named above are **byte-identical**
between the live mirror and the repo copy at the same relative path: `plan-reviewer.sh`,
`review-record-commit-gate.sh`, `model-pin-gate.sh`, `adapters/claude-code/hooks/lib/admission-
lib.sh`, `adapters/claude-code/hooks/lib/git-command-parse.sh`, `adapters/claude-code/hooks/lib/
self-sync-guard.sh` (`cmp` exit 0 on every pair, checked directly). Staleness cannot be the cause
for these six — whatever fails, fails identically regardless of which copy runs.
`scope-enforcement-gate-body.sh` / `session-start-digest.sh` / `session-start-auto-install.sh` /
`concurrent-ownership-gate-body.sh` DO diverge (9-63 lines) but far less than the two proven
cases; not independently re-run this session (time-boxed), so their sweep REDs remain of
UNKNOWN cause pending a direct re-run.

**Per-suite disposition of the six byte-identical ones:**
- `model-pin-gate.sh` — already covered by `MODEL-PIN-GATE-SELFTEST-NONHERMETIC-01` above; the
  byte-identity finding here is consistent with (does not refute) that entry's non-hermetic-
  tier-state HYPOTHESIS.
- `self-sync-guard.sh` — PROVEN (direct re-run this session): 4 passed, 5 failed. Every failure
  is a symlink-creation assertion (`ln: failed to create symbolic link '.../dangling.json': No
  such file or directory`) — the SAME class this file's 2026-08-03 section already names as
  "Windows-specific self-test friction" (nonode-shim symlink, NTFS-reserved-character fixtures).
  HYPOTHESIZED: Windows/NTFS symlink-creation limitation in the fixture, not a doctor-sweep
  defect (refuter: run on macOS/Linux — if it also fails there, the cause is a genuine fixture
  bug, not environmental).
- `adapters/claude-code/hooks/lib/admission-lib.sh` — PROVEN (direct re-run this session): **80
  passed, 0 failed, full GREEN.** The sweep's own "79/1" does not reproduce directly — same
  TRANSIENT-not-durable pattern as `model-pin-gate.sh` above (byte-identical live/repo copy,
  passes standalone, fails under sweep load). Not chased further; likely a shared-resource/
  timing sensitivity common to self-tests run back-to-back inside a ~50+-suite sweep, not a
  defect in the lib itself.
- `adapters/claude-code/hooks/lib/git-command-parse.sh` — PROVEN (direct re-run this session,
  identified): **114 passed, 1 failed, both times — same single scenario**: `FAIL: 32KB
  separator-dense commit took 697ms — the fast path is not being taken`. This is a PERFORMANCE
  THRESHOLD assertion, not a correctness one. HYPOTHESIZED (refuter: re-run alone on an idle
  machine — if it passes, timing-sensitivity is confirmed; if it still fails at ~700ms, the fast
  path genuinely regressed and this becomes a real perf bug): both of this session's "direct"
  re-runs executed WHILE a massive concurrent `harness-doctor.sh --full` sweep (and, for the
  first re-run, ANOTHER self-test) were consuming CPU on the same machine — i.e. NEITHER run was
  actually on an idle machine, so this may be the SAME transient/CPU-contention class as
  `model-pin-gate.sh`/`admission-lib.sh` above, not a genuinely-reproducible defect. Correcting
  this entry's own earlier (wrong) claim that this was "NOT transient" — that claim compared two
  contended runs to the sweep's own contended run, which proves nothing about idle-machine
  behavior. OPEN — needs a genuinely idle-machine re-run to classify.
- `plan-reviewer.sh`, `review-record-commit-gate.sh` — direct re-run attempted this session but
  not concluded within the time budget (both are large/slow suites; `plan-reviewer.sh` alone is
  independently measured elsewhere in this file at ~987s). OPEN, not yet investigated — same
  disposition the 2026-08-03 pass already gave both; this entry additionally rules out staleness
  as their cause.

**Why not chased further here:** this task's mission was the SWEEP-LAYER defects (path mangling,
skip-vs-fail rc contract, live-vs-repo disclosure) plus fixes "you cannot fix cheaply" get
dispositioned, not root-caused. These six are per-suite genuine-or-flaky failures requiring
individual, potentially lengthy (10-15+ min per suite) investigation — out of proportion for this
pass. Flagged so a future pass runs each to a direct conclusion.

## NL-ISSUES-TRIAGE-20260803 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 151 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 27d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## COCKPIT-OPERATOR-ASKS-2026-08-03 — four operator-flagged cockpit/roadmap-view items
(label: `cockpit`, `operator-directed`; owner: cockpit-roadmap-redesign plan / its live session —
NOT gated-pipeline scope; filed here same-turn per constitution §5)

Operator, 2026-08-03 (screenshot of 127.0.0.1:7733/#roadmap on the gated-pipeline plan):
1. **Per-task verification-stage status.** Checkbox-only rendering hides the pipeline: a task
   that is built+merged but awaiting task-verifier looks identical to one never started. Wanted:
   per-task stage chip (dispatched → built → merged → VERIFIED) with the verification stage
   explicitly visible, so "11/24 verified vs 5/24 checked" discrepancies cannot happen silently.
2. **Layout: fixed-width dead space** between the Status column and the Progress Bar column,
   while the tag at each row's end is TRUNCATED — reclaim the gap for content.
3. **Derive-on-refresh:** page refresh showed "deriving the information" for seconds. Operator:
   "Didn't we decide that the information should not be derived but instead should be
   deterministically updated automatically as tasks make progress?" — reconcile the cockpit's
   read path with the one-registry/materialized-view decision (cockpit-roadmap-redesign plan);
   if event-driven updates were decided, the derive-on-view path is a regression to fix, not
   tune.
4. **Attribution task-id format defect (orchestrator side, fixed for future dispatches
   2026-08-03):** NL-ATTRIBUTION headers this session used `task=T7`/`T20`-style ids; the plan's
   ids are numeric (`7`, `20`) — cockpit correctly reported "not a task id in this plan" and
   marked live-dispatched tasks 'stalled — no recent dispatch'. Future dispatches use numeric
   ids; the mis-attributed ledger rows from 2026-08-03 (tasks T7/T20/T23/T24/T25 spellings) may
   need a one-time reconcile so today's history renders truthfully.

## NL-ISSUES-TRIAGE-20260804 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 164 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 27d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## NEEDS-YOU-READABILITY-2026-08-03 — operator: the awaiting-operator ledger is not human-readable
(label: `harness-ux`, `operator-directed`; owner: this session → audit dispatched, generator fix to follow)

Operator, verbatim: "The NEEDS-YOU.md doc it is incredibly messy and very difficult to read. This
is absolutely not formatted to be human-readable. It is not clear to me what it is that you
actually need from me. … make it very straightforward and straight to the point, Give me the
context that I need and some of the information that I need to decide on in a clear,
consolidated, and concise format?"

Diagnosis to verify in the audit: (1) entry rot — items dating to 2026-07-08 with no staleness
triage, likely several superseded; (2) rendering defects — each entry's title is duplicated as
its first body line; entries are single wall-of-text paragraphs; (3) no top-level "what I need
from you FIRST" summary; (4) the §3 compact-decision format (constitution) is the already-agreed
rubric the renderer ignores. Fix lands in `adapters/claude-code/scripts/needs-you.sh` (the file
itself is generator-owned, never hand-edited). Audit agent: Audience Content Reviewer →
docs/reviews/2026-08-03-needs-you-readability-review.md + a same-day triaged digest the operator
can actually read.

## SESSION-SCOPED-VERIFY-OBLIGATIONS-2026-08-04 — scope stop-side obligations to the stopping session
(label: `harness-gap`, `stage-2-successor`; from harness-reviewer F5 on gated-pipeline T25)

The verify-obligation stop check scopes by plan references in the final message — simultaneously
over-inclusive (any session linking a plan with open machine-wide obligations gets gapped once;
the ledger is $HOME-global and artifact_ref carries no repo qualifier) and under-inclusive (no
link → no check). The rows ALREADY carry session_id: scoping obligations to rows whose
session_id matches the stopping session removes both directions in one move. Non-blocking today
(block-once + cheap marker remedy bound the erosion; disclosed in the gate artifacts).

## BASH-SOURCE-DIR-RESOLUTION-FRAGILITY-SWEEP-2026-08-04 — estate-wide `${BASH_SOURCE[0]%/*}` audit
(label: `harness-gap`; from harness-reviewer F4 on gated-pipeline T25)

`dispatch-chain-gate.sh:42`'s `_dcg_dir` resolution breaks under slash-less/backslash invocation
(lib sourcing fails; pre-T25 the suite false-greened vacuously — now guarded loud, exit 3). The
same `${BASH_SOURCE[0]%/*}` idiom exists across the estate; sweep query:
`rg -n 'BASH_SOURCE\[0\]%/\*' adapters/claude-code/` — triage each hit for a sourcing-failure
guard or `cd`-based resolution. T25 guarded its own entry points only.

- **COCKPIT-AUDITOR-STILL-PULLS-01 — the background drift auditor still shells on a fixed 120s clock tick, not on real change** (added 2026-08-02 from the workstreams-ui cockpit-server subprocess-storm fix; label: `harness-gap`, `priority:low`; fold-in: the next auditor.js touch, or a dedicated push-conversion pass). The storm fix (`neural-lace/workstreams-ui/server/state-watch.js`) converted the DeriveCache's six `nl <sub> --json` panes from a pure 30s poll to push (fs.watch + debounce, anti-entropy floor raised to 5min) — the golden-case measurement it fixed named `nl.sh status --json` specifically (45/93 live bash processes). `neural-lace/workstreams-ui/server/auditor.js` (Task 12's background drift auditor) is a SEPARATE poller on its own 120s `AUDITOR_CADENCE_MS` timer, shelling `progress-log.sh emit` / `ask-registry.sh set-status` / `merge-scan-lib.sh scan-repo` — already relaxed relative to the old 30s pane cadence and already single-flighted (`_cycleInFlight`, mirrors DeriveCache's own guard), but still PULL: it re-shells every 120s regardless of whether the ask-registry/plan files/git state it audits actually changed. Converting it to the same push+floor pattern (watch `ASK_REGISTRY_STATE_DIR`, plan files, `.git/refs`) is a natural follow-on, deliberately deferred here for scope/time — it was not part of the measured golden case and touching it would have widened this fix beyond the confirmed storm source. **Re-derive:** `grep -n "DEFAULT_CADENCE_MS\|_cycleInFlight" neural-lace/workstreams-ui/server/auditor.js`.

- **COCKPIT-ASK-DETAIL-CLASSIFY-SESSIONS-PER-REQUEST-01 — `GET /api/ask/<id>` shells `hb_classify` once per request, uncached** (added 2026-08-02 from the same subprocess-storm fix; label: `harness-gap`, `priority:low`; fold-in: opportunistic, if ask-detail views become a hot path). `buildAskDetailPayload` (`neural-lace/workstreams-ui/server/server.js`) calls `deriveLib.classifySessions(sessionIds)` (`neural-lace/workstreams-ui/server/derive-lib.js`) on EVERY request, which spawns a bash login shell sourcing `session-heartbeat-lib.sh` and calling `hb_classify` per session id. NOT converted in this fix: `web/asks.js` only fetches `/api/ask/<id>` on first expand (not polled — confirmed by grep, no `setInterval`/SSE-driven refetch of the detail endpoint), so this is bounded by user click-rate rather than a clock or a change-storm, unlike the confirmed golden-case source. A short-TTL cache or single-flight-per-session-set would still be a legitimate small hardening if this view becomes hot. **Re-derive:** `grep -n "classifySessions" neural-lace/workstreams-ui/server/server.js neural-lace/workstreams-ui/server/derive-lib.js`.

- **COCKPIT-SERVER-SELFTEST-FLAKY-ASK-FIXTURE-01 — `server.selftest.js` intermittently crashes mid-suite in the ask/dispatch-provenance fixture section, PRE-EXISTING and unrelated to the subprocess-storm fix** (added 2026-08-02 from the same fix's verification pass; label: `harness-gap`, `priority:medium`; fold-in: next touch of the ask-fixture setup in `server.selftest.js`). **PROVEN pre-existing:** reproduced identically on UNMODIFIED baseline code (git stash of every storm-fix change, two separate runs) — run 1 crashed `Error: ENOENT ... dispatch-provenance/fixture-marker__1.json` at the fixture-write step; run 2 crashed `TypeError: Cannot read properties of undefined (reading 'asks')` later in the same section, both around the S23+ ask-registry/dispatch-provenance scenarios. Two DIFFERENT crash points across two runs of the SAME unmodified code confirms a timing/race bug in the ask-fixture setup (likely a directory-creation race ahead of a synchronous write), not a deterministic break — and not something the storm fix touched (every scenario through S26b, including the DeriveCache-heavy S6b/S6c/S17/S22, passed cleanly both before and after this fix in every run). **Re-derive:** `node neural-lace/workstreams-ui/server/server.selftest.js` a few times in a row and compare crash points/lines.

## HYGIENE-GATE-ESCAPE-ACCOUNTABILITY-FOLLOWUPS-2026-08-04 — honest residuals from the hygiene-gate self-service-escape fix
(label: `harness-gap`; from the hygiene-gate incident fix, harness-hygiene-scan.sh Defects 1-2 + workaround-sensor-lib.sh/stop-verdict-dispatcher.sh/session-start-digest.sh Defect 3-4)

Three named, disclosed-not-hidden gaps in the same-turn-visible + Stop-blocking escape-obligation
mechanism (`ws_open_escape_obligations`, `_svd_escape_naming_check`):

1. **Same-turn NOTICE (Defect 4 item c) is wired at harness-hygiene-scan.sh's own `ws_record` call
   sites only.** The four OTHER existing `ws_record` callers (`concurrent-ownership-gate-body.sh`,
   `dispatch-chain-gate.sh`, `review-record-push-gate.sh`, `scope-enforcement-gate-body.sh`) have
   their escapes tracked generically by `ws_open_escape_obligations`/the Stop-side check (any
   `bypass_kind` row opens an obligation regardless of which gate wrote it), but do NOT yet print
   an in-turn "this opened an obligation" notice at their own waiver-honored call sites — an agent
   using one of those gates' escapes only learns about the obligation at the NEXT Stop, not in the
   same turn. Fold-in: one small edit per call site, same one-line `printf ... >&2` pattern
   harness-hygiene-scan.sh now uses.
2. **FIXED auto-close (`_ws_escape_gate_fixed`) only re-verifies `gate=="harness-hygiene-scan"`**
   (the one caller with an honest `--check <file>` re-verification mode this lib knows how to
   drive). Every other gate's escapes can never auto-close via re-scan — they fall through to
   requiring an `escape-obligation-ack-*.txt` marker, or stay open indefinitely. This is a
   deliberate fail-closed scoping choice (documented in the lib's own header), not an oversight,
   but it means e.g. a `concurrent-ownership-gate` escape has no "the lock cleared itself" path.
3. **`manifest.json`'s `harness-hygiene-scan` entry is not updated** with the new
   `escape-obligations` Stop check, the `bypass-24h` digest feed, or the operator-waiver marker
   class — the manifest's enforcement inventory is stale for this gate until a future pass reconciles
   it. **Re-derive:** `grep -n '"id": "harness-hygiene-scan"' adapters/claude-code/manifest.json`.

C-round additions (harness-reviewer REFORMULATE on `b8c9fe0a`, 2026-08-04 — C1 required fix +
condition, F7-F10 minors named-not-fixed by the reviewer's own instruction):

4. **C1 residual — the two push-time CI jobs are still whole-file, not delta-scoped.**
   `.github/workflows/secret-backstop.yml:133` and `server-side-enforcement.yml:118` both invoke
   `bash adapters/claude-code/hooks/harness-hygiene-scan.sh "${changed[@]}"` (explicit changed-file
   args = MODE="files" = whole-file scan, PROVEN by reading both files directly) on every
   `push`/`pull_request`, with no waiver-marker channel (a fresh CI checkout has no
   `.claude/state/`). The messaging fix (this same commit) now tells the truth about this instead of
   claiming a nonexistent "periodic full-tree scan" catches pre-existing debt. Deliberately NOT
   attempted in the same series: editing GitHub Actions YAML that cannot be exercised from this
   environment ("cannot run Actions live from this environment" — the workflow's own header) risks
   silently weakening the real security backstop, a worse outcome than leaving it whole-file and
   honestly documented. **Concrete fix shape for the next session:** give
   `harness-hygiene-scan.sh` a base-ref delta mode analogous to `_hhs_build_delta_view` (which
   already accepts a rename-source 4th arg) but driven by `git diff <base_sha>..<head_sha> -U0`
   instead of `--cached`; wire both workflow `run:` blocks to pass `BASE_SHA`/`HEAD_SHA` through to
   a new `--diff-range <base> <head>` flag instead of relying on MODE="files" whole-file reads.
   **Re-derive:** `grep -n "harness-hygiene-scan.sh \"\${changed\[@\]}\"" .github/workflows/*.yml`.
5. **F7 — vaporware "weekly" backstop docs conflict.** Some harness doc(s) describe a
   scheduled/weekly full-tree hygiene audit that does not exist as a live mechanism (only the
   manually-invoked `/harness-review` skill wraps `--full-tree`, and it is not on any schedule per
   `adapters/claude-code/config/schedule-manifest.json`). Sweep `grep -rn -i "weekly.*hygiene|periodic.*full-tree|required check|branch.protection requires" adapters/claude-code/ .github/ docs/` and correct or retire each claim. WIDENED 2026-08-04 (delta re-review): the class includes unverified-enforcement-semantics claims — "REQUIRED check" asserted without querying live branch protection; one shipped in the C-round itself, one pre-existed in server-side-enforcement.yml (both fixed at merge).|periodic.*full-tree" adapters/claude-code/` and correct or retire each claim.
6. **F8 — unbounded ledger scan on the Stop path.** `ws_open_escape_obligations` (called from
   `_svd_escape_naming_check` on every Stop) reads the ENTIRE `workaround-sensor.jsonl` via `cat`
   with no line cap, unlike `session-start-digest.sh`'s own `feed_bypass_surface` (`tail -n 1000`).
   On a long-lived machine the ledger grows unboundedly; bound the read (e.g. `tail -n N` before the
   per-line filter) the same way the digest feed already does.
7. **F9 — the ack directory is not named in the Stop-time block message.** `_svd_escape_naming_check`'s
   gap message points at "lib/workaround-sensor-lib.sh" for the marker spec but never states the
   concrete directory (`dirname "$(_workaround_sensor_path)"`, i.e. normally
   `$HOME/.claude/state/`) an operator or agent would need to actually find/write
   `escape-obligation-ack-*.txt` into. Name the resolved directory in the gap message.
8. **F10 — a waiver-coverage ledger row fires even when nothing was actually suppressed.**
   The regular-waiver / operator-waiver `ws_record`/`ledger_emit` calls in harness-hygiene-scan.sh
   fire whenever `regular_waived`/`operator_waived` is true for a file, regardless of whether Layer
   2/3 (`check_heuristics`/`check_addendum_lint`) would have found ANYTHING to suppress on that
   file — a waiver marker naming a file that turns out to have zero matches still logs a
   "waiver used" ledger row and opens/refreshes an escape obligation. Scope the log/obligation to
   files where a suppression genuinely occurred (track whether Layer 2/3 would have matched before
   deciding whether to log).


## GREEN-RUNNING-CHIP-MERGE-PENDING-2026-08-05 — built, browser-verified, NOT yet on master
(label: `cockpit`, `operator-priority`; owner: next session, FIRST task)

The operator's repeatedly-requested green "currently building" highlight is BUILT and proven,
but sits unmerged in worktree `agent-aa9a284a346ee2a14`, branch `worktree-agent-aa9a284a346ee2a14`:
  - `c8df1d2c` — three-way conflict resolution (plan-status schema + manifest + plan-edit-validator)
  - `5c95b277` — the green feature itself
PROVEN by its builder: field `running_now` (stamped by `stampRunningNow`, roadmap-routes.js),
CSS `.rm-title-running` (`--running: #4ade80`); new SINK 1b in workstreams-emit.sh emits
`task_started` with sentinel `task_id="(plan-only)"` for plan-only headers; four pinned
scenarios PINNED4-1..4 each mutation-killed; live browser DOM check found exactly 3
`.rm-title-running` elements at rgb(74,222,128) weight 700 against the real running server.
Suites: workstreams-emit 161/0, roadmap-routes 175/0, cockpit 593/0, manifest GREEN.

WHY NOT MERGED: its base (df0eade8) predates master's exec-stderr fix (ab4480be) and flap guard
(c043b6ec). The merge conflicts in plan-edit-validator.sh's self-test block — HEAD's F33
(exec-redirection regression pin) vs the branch's G1-G9 (Status-validation scenarios) — and git
splits the region MID-SCENARIO, so a naive union produces a syntactically invalid script
(verified: "line 3287: syntax error: unexpected end of file"). Merge was aborted; master is
clean and green at c043b6ec (plan-edit-validator 33/33).

HOW TO FINISH: rebase `worktree-agent-aa9a284a346ee2a14` onto current master, or hand-merge the
self-test block keeping BOTH F33 and G1-G9 intact as whole scenarios (check the final
"of N scenarios" count matches the real total), then re-run plan-edit-validator --self-test,
roadmap-routes.selftest.js, cockpit.selftest.js, and manifest-check before pushing.

## NL-ISSUES-TRIAGE-20260805 — nl-issue triage escalation (auto-filed)

**Severity:** P3 (nagging, not blocking)
**Trigger:** 17 untriaged nl-issue entries (threshold >5) or oldest untriaged entry is 20d old (threshold >7d).
**Action:** run `nl-issue.sh --list --untriaged` and triage each entry with `--triage <n> <backlog|task|wontfix> <ref-or-reason>`.
**Filed:** auto-filed by nl-issue.sh --digest-feed; idempotent per day (id above).

## AUTO-MODE-ASK-RULES-BECOME-SILENT-DENIALS-2026-08-05 — three `ask` permission rules read as
hard denials in auto mode, and the block message misdiagnoses them (label: `harness-gap`,
`operator-decision`)

**PROVEN today:** `~/.claude/settings.json` `permissions.ask` contains exactly three entries —
`Bash(SUPABASE_ACCESS_TOKEN=* supabase db push:*)`, `Bash(npx supabase db push:*)`,
`Bash(supabase db push:*)`. In an autonomous (no-human-in-loop) session an `ask` rule cannot
prompt, so it resolves as a DENIAL. `permissions.allow` already contains `Bash(*)`, but the
more-specific `ask` pattern wins, so the broad allow is irrelevant.

**Why it matters:** the denial surfaces as "Blocked by the Claude Code auto mode classifier …
the user can add a Bash permission rule to their settings" — generic boilerplate that sends the
operator to add an allow rule they ALREADY have (`Bash(*)`). Two sessions' worth of operator
friction traced to this: the operator explicitly authorized `apply parts migration`, and the
apply still could not run. The true remedy is to MOVE the pattern from `ask` to `allow` (or
delete it), not to add anything.

**Also blocked, mechanism NOT yet confirmed as an ask-rule:** `gh api -X PATCH
repos/<owner>/<repo>/branches/master/protection/...` (branch-protection mutation) and mass
config rewrites (the 51 `.env.local` repoint). These may be classifier-semantic denials rather
than settings-driven — verify before advising the operator on those two.

**Durability note (operator directive 2026-08-04, "solutions should be everlasting"):** the
repo template `adapters/claude-code/settings.json.template` carries `permissions.allow` (6
entries) but NO `ask`/`deny` block — so the three ask rules are MACHINE-LOCAL only and would not
follow to another machine. Any decision here should land in the template to be durable, and the
template→live sync path for `permissions` (as opposed to hook wirings) needs confirming — it was
not verified in this session.
