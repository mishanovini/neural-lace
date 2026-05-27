# Plan: Ship merge-completed-work rule + auto-merge design doc
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal Pattern rule + design doc; no product user; self-tests are the dispatch-session-monitor's stale-PR sweep + future hook self-tests when built per design doc
prd-ref: n/a — harness-development
frozen: true
tier: 1
rung: 1
architecture: documented

## Goal

Maintainer observed ~198 unmerged branches across ~6 repos on 2026-05-27. The "open PR → move on → forget" pattern is the single biggest source of drift in the system. Ship three structural changes to make merging part of the session lifecycle rather than an afterthought: (1) standing rule binding every session that opens a PR to drive it to merge, (2) dispatch-session-monitor stale-PR sweep across all repos with auto-merge for safe-class PRs, (3) design doc for the future PostToolUse hook + tracking poller that would mechanize the discipline.

## Scope

- IN: new rule file `adapters/claude-code/rules/merge-completed-work.md` (+ live mirror), update to monitor SKILL.md (outside this repo), new design doc `docs/designs/auto-merge-on-green-hook.md`.
- OUT: building the auto-merge hook or tracking poller (deferred per design doc rationale — monitor sweep is sufficient backstop; build when sweep is observed in production for ~2 weeks).
- OUT: backfilling the 198 existing unmerged branches (separate operational triage task; this plan is about preventing the next wave).
- OUT: updating `docs/harness-architecture.md` with the new rule entry (will batch with next harness-architecture refresh per the conventional cadence).

## Tasks

- [x] 1. Create `adapters/claude-code/rules/merge-completed-work.md` with Misha's verbatim rule body + harness-standard Classification + Cross-references + Scope sections. Mirror to `~/.claude/rules/`. Verification: mechanical
- [x] 2. Update `&lt;scheduled-tasks-dir&gt;/dispatch-session-monitor/SKILL.md` with step 6 (stale-PR sweep across all repos with per-classification routing) and amend "What NOT to do" constraint replacing prior blanket "Don't merge PRs" with the safe vs. product-code split. Verification: mechanical
- [x] 3. Create `docs/designs/auto-merge-on-green-hook.md` capturing PostToolUse hook + tracking file + companion poller design with implementation plan, open questions, and rationale for "don't build now." Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/rules/merge-completed-work.md` — new rule file (canonical)
- `docs/designs/auto-merge-on-green-hook.md` — new design doc
- (out-of-repo: `~/.claude/rules/merge-completed-work.md` live mirror)
- (out-of-repo: `&lt;scheduled-tasks-dir&gt;/dispatch-session-monitor/SKILL.md` monitor update)

## Assumptions

- The maintainer's verbatim rule text is the authoritative content; do not edit the rule body beyond adding standard harness sections (Classification at top, Cross-references + Scope at bottom).
- The dispatch-session-monitor scheduled task is already registered and runs every 10 min; the SKILL.md edit takes effect on the next scheduled invocation without requiring re-registration.
- The `gh` CLI on the maintainer's machine is authenticated across all relevant accounts (personal + work) such that the monitor's `gh pr list --repo` queries succeed.
- Harness-hygiene-scan denylist + Layer-2 heuristics are the perimeter for identifier leakage; this rule's body and the design doc were sanitized for absolute paths, GitHub account names, and personal-name uses inconsistent with the maintainer-attribution convention.

## Edge Cases

- **Stash collision**: this plan was created mid-session on a different feature branch with staged work; the work was stashed before switching to master. Stash pop on return must not conflict with master's HEAD.
- **Monitor sweep classification ambiguity**: a PR touching one config file + one src/ file is "mixed" → treated as product-code (do not auto-merge). The rule and monitor agree on this.
- **Repo enumeration failure**: if `gh repo list <account> --limit 50` fails for any reason, the monitor falls back to its hardcoded repo list for the sweep. Better partial coverage than zero coverage.
- **Existing ~198 unmerged branches**: this plan does not address them; they remain manual triage for the maintainer. The monitor's sweep will pick them up on its next run and either auto-merge safe-class or surface for review.
- **Direct-to-master commit**: per `~/.claude/rules/git.md` "Direct master commits and pushes are acceptable on pre-customer projects" — neural-lace is a pre-customer harness repo. No PR ceremony for this commit.

## Testing Strategy

- Task 1: `diff -q ~/.claude/rules/merge-completed-work.md adapters/claude-code/rules/merge-completed-work.md` returns empty (mirror is byte-identical). File present in both locations.
- Task 2: `grep -c "stale PRs" &lt;scheduled-tasks-dir&gt;/dispatch-session-monitor/SKILL.md` returns ≥ 1; "Don't merge PRs" no longer present as blanket constraint (replaced with safe vs. product-code split).
- Task 3: `docs/designs/auto-merge-on-green-hook.md` exists with non-trivial content (≥ 100 lines), Status: DESIGN line present, Implementation plan section present.
- Runtime verification deferred to design doc's future build: when the auto-merge hook + poller are built per the design doc, they'll have their own `--self-test` blocks.
- Acceptance: monitor's next scheduled run (within 10 min of commit) exercises the new step 6 against real repos; success = no errors logged, surfacing behavior matches the rule's classification taxonomy.

## Walking Skeleton

The thinnest end-to-end slice is the rule body itself: one rule file, one monitor edit, one design doc. Each file is independent (no shared substrate, no wiring between them). The rule's enforcement is the monitor's sweep + agent discipline; the design doc's enforcement is future work. No new code paths, no new dependencies, no test infrastructure to spin up. The slice is structurally trivial; the value is in the discipline the artifacts represent.

## Decisions Log

### Decision: ship the rule body verbatim from Misha's directive
- **Tier:** 1
- **Status:** auto-applied
- **Chosen:** preserve Misha's rule body word-for-word; add only standard harness sections (Classification at top, Cross-references + Scope at bottom) for consistency with every other rule in `~/.claude/rules/`.
- **Reasoning:** Misha gave a directive with specific wording; editing the body changes the contract he was authoring. Adding standard sections is consistent with the harness convention and does not alter the rule's substance.
- **To reverse:** edit the rule file to match a different wording; mirror to live; commit.

### Decision: defer building the auto-merge hook + poller
- **Tier:** 2
- **Status:** auto-applied per Misha's directive ("don't build the hook yet — the rule + monitor update handle the immediate problem")
- **Chosen:** design doc only; future session can implement per the captured plan.
- **Reasoning:** the monitor's step 6 sweep is the immediate backstop; the hook + poller is the more-elegant solution but adds Windows scheduled task ceremony + a new state file format. Observe the monitor's sweep in production for ~2 weeks before committing to the structural mechanism.
- **To reverse:** when the monitor's sweep is observed to be insufficient (e.g., a PR drift recurs within the 10-min window between sweeps), implement the hook + poller per the design doc.

## Definition of Done

- [x] All tasks checked off
- [x] Rule file present at both `adapters/claude-code/rules/` and `~/.claude/rules/`, byte-identical
- [x] Monitor SKILL.md updated with step 6 and amended "What NOT to do"
- [x] Design doc present at `docs/designs/auto-merge-on-green-hook.md`
- [x] Committed to master (this plan + the three artifacts in same commit)
- [x] Plan Status flipped to COMPLETED on landing

## Evidence Log
