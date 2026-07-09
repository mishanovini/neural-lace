# Plan: nl-issues ledger triage + fix sweep (2026-07-09)

- **Status:** ACTIVE
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
- [ ] A1 [48]+[52] sandbox unresolved-gaps feed path under HARNESS_SELFTEST in session-start-digest self-test S2
- [ ] A2 [49] add `info` (work-integrity-gate) to observability-consumer-map with named consumer, or constrain emitter
- [ ] A3 [51] cold-reader-lint: require §3 block shape, exclude negation; self-test scenario
- [ ] A4 [31] install.sh sync loops gain skills/ + templates/
- [ ] A5 [47]+[25] denylist: narrow codename pattern (word-boundary/case-aware; stop matching the generic two-word idiom) + relocate literal test-password VALUE to gitignored business-patterns.d — harness-reviewer REQUIRED (security control)
- [ ] A6 [54] verify/extend .gitattributes eol=lf coverage for workflow .js paths

**WAVE B — medium (verify-first; Stop-gate diffs get harness-reviewer):**
- [ ] B1 [26]+[27]+[30]+[45]+[53] end-manifest cluster: establish what fb7ab9a/wave-o-integration already fixed; then residuals — truncation mutual-prefix match, per-line jq -e → slurp any(), and a sanctioned resolution path for stale gaps ([53] class; decide-and-go with trail)
- [ ] B2 [42] dispatcher: surface combined verdict in the block message (stderr never reaches session context)
- [ ] B3 [22] live ~/.claude CRLF drift: extend doctor line-endings check to $live_home OR normalize-on-copy (verify "live CRLF deliberate" memory first)
- [ ] B4 [56] scheduled-task naming drift: repoint/rename doctor↔registration; coordinate with sweet-hamilton session (it plans to unregister ConversationTreeUI-AutoStart); sequence after B3 (same file)
- [ ] B5 [37]+[39]+[55] cockpit/derive-cache: single-instance lock or listen-gate before cache.start(); single-flight poll guard; OBS_NL_TIMEOUT_MS review
- [ ] B6 [23]+[35]+[38] doctrine/docs: orchestrator-pattern brief-template worktree-check + branch-verify-before-commit + ls-remote-after-push; acceptance conventions registered-event-types-only + scrub coordination
- [ ] B7 [24] set-e assignment-from-failing-pipeline audit across hooks/*.sh; verify plan-edit-validator instance fix merged

**ROUTE / DEFER (persist, no build):**
- [ ] R1 [34] shared-checkout branch guard proposal + [46] credentials/403 JIT-trigger proposal + [40] cold-reader mechanical layer + [43]/[44] bg-agent auto-retry → backlog rows with fold-in points
- [ ] R2 [21] GAP-54 → confirm backlog row current; stays deferred. [32] Claude_Preview parent-worktree launch.json → document-upstream note in doctrine
- [ ] R3 mark every ledger row's disposition via nl-issue.sh (terminal state; zero untriaged)

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

## Decisions Log

- 2026-07-09: ledger = nl-issues.jsonl (see Assumptions).
- 2026-07-09: verify-first for rows claiming prior fixes — re-derive master state before building. PAID OFF: cut the end-manifest cluster in half and confirmed two ADR fold-ins already landed.
- 2026-07-09: mechanism proposals ([34][40][46], bg-agent auto-retry) are ROUTED not built — each is a new gate/trigger needing its own golden-scenario + FP-rate case per constitution §10; bundling them into a fix sweep would under-review them.
- 2026-07-09: builder-sweep dispatch (Wave A/B) is deferred until after ADR-061 review+merge — the operator scoped the sweep as "when you're done with everything here," and a 5-builder fan-out immediately after a spend-limit hit warrants finishing the design gate first. Not a scope change; a sequencing call.
- 2026-07-09 (post ADR-061 merge, on Opus after the Fable spend-limit pause): Wave A builders dispatched (background, worktree-isolated) — A1 [48]/[52] digest-S2 sandbox (build/nl-issue-48-digest-s2-sandbox), A2 [49] consumer-map info (build/nl-issue-49-consumer-map-info), A3 [51] cold-reader negation (build/nl-issue-51-coldreader-negation), A4 [31] install-sync skills/templates (build/nl-issue-31-install-sync-skills). A5 (denylist — public-mirror security control) HELD for harness-reviewer; Wave B HELD until Wave A verifies. Orchestrator verifies each on-disk before merge; task-verifier flips checkboxes.
- 2026-07-09: operator APPROVE-BUILD (NEEDS-YOU NY-1783623638-90f3 resolved) — full build greenlit: ADR-061 Phase 1 + entire sweep. Operator clarified the limit class: usage-credits monthly pool 101% ($201.51, resets Aug 1); Fable weekly 0% — captured as a real D4 account-cap instance in the ADR status line. ADR status flipped PROPOSED → ACCEPTED (design); arming still a separate Phase-2 gate.
- 2026-07-09: origin/master advanced with the sweet-hamilton session's cockpit-sessionstart merge (bf2b8c7 — logon-task retirement recorded): B4's coordination target has landed; B4 re-verifies task-name state against that merge before touching anything.
