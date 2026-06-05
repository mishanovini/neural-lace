# Plan: gh-account-blindness hint Mechanism
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanism; self-tests (9/9) + byte-identical mirror sync are the acceptance artifact. No product runtime to advocate for.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Convert dual-GitHub-account awareness from Pattern-only (CLAUDE.md prose + a passive SessionStart active-account line) into a Mechanism that reacts at the failure moment. A `gh` 404/403 caused by being authenticated as the WRONG account (active as account-A while the repo is owned by account-B) currently produces a false "the repo doesn't exist" conclusion. Per `principles.md` Decision Principle 6 (mechanical where the signal is reliable), a gh 404/403 is a reliable signal — so a hook fires the exact remediation instead of relying on the agent remembering the convention.

## User-facing Outcome
After this ships, the instant a gh/git command returns "repo not found"/404/403 because the wrong account is active, the agent (the harness's "user" here) sees an advisory naming `gh auth switch -u <owner>; retry; switch back` — instead of concluding the repo is missing. SessionStart also broadcasts the full account map with the "404 means switch, not missing" note.

## Scope
- IN: a new PostToolUse Bash hook (`gh-account-blindness-hint.sh`) backing L1 (failure-moment hint) and L2 (`--session-start` account-map broadcast); its wiring in `settings.json.template`; a one-line Pattern (L3) in `rules/git.md`; the new-hook row in `docs/harness-architecture.md`.
- OUT: changing the SessionStart active-account *switcher* logic (the new L2 line is additive); any change to `accounts.config.json` shape (read as-is at runtime); auto-switching-and-retrying on behalf of the agent (advisory only — never blocks, never mutates auth state).

## Tasks

- [ ] 1. Build + wire the gh-account-blindness hint mechanism (L1 PostToolUse hook + self-test, L2 SessionStart broadcast, L3 rules/git.md Pattern, settings.json.template wiring, harness-architecture.md row, live-mirror sync). — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/gh-account-blindness-hint.sh` — new hook: L1 PostToolUse hint + L2 `--session-start` broadcast + `--self-test` (9 scenarios). Reads owner→account map from `~/.claude/local/accounts.config.json` at runtime; no hardcoded identifiers.
- `adapters/claude-code/settings.json.template` — wire L1 (PostToolUse Bash) + L2 (SessionStart `--session-start`).
- `adapters/claude-code/rules/git.md` — L3: one-line Pattern (a gh/git not-found/403 is wrong-account evidence until the other account is checked).
- `docs/harness-architecture.md` — new-hook inventory row (docs-freshness gate requirement).

## In-flight scope updates
(no in-flight changes)

## Assumptions
- `~/.claude/local/accounts.config.json` uses the canonical shape (`work`/`personal` arrays of `{gh_user, ...}`) per `examples/accounts.config.example.json`; the hook also tolerates legacy `user` and object-vs-array forms, plus an optional forward-compatible `owners[]` array for org repos an account can access.
- owner==gh_user is the load-bearing mapping: a repo owned by `<X>` needs the account whose gh_user is `<X>`.
- PostToolUse hooks receive the tool's command (`tool_input.command`) and output (`tool_response`) on stdin as JSON.
- `gh auth status` prints the account login one line above `Active account: true` (parsed for the active account).

## Edge Cases
- Missing jq / missing accounts.config / can't determine active account / unparseable owner → graceful silent no-op.
- Owner not a known account in the config → no hint (the hook can't advise which account).
- Correct account already active (real missing/forbidden repo) → no hint.
- gh command succeeded (no error signature) → no-op.
- Non-gh/git tool output → no-op.

## Acceptance Scenarios
n/a — acceptance-exempt (harness-internal). The `--self-test` suite (9 scenarios) is the acceptance artifact: wrong-account→hint, correct-account→no-hint, non-gh→no-op, missing-config→no-op, unknown-owner→no-hint, org-via-owners[]→hint, success-output→no-op, L2-broadcast, git-clone-https→hint.

## Out-of-scope scenarios
- Auto-switching+retrying the failed command on the agent's behalf (would mutate auth state silently; advisory chosen instead).

## Testing Strategy
- `gh-account-blindness-hint.sh --self-test` exercises all 9 decision paths (no real gh needed; `*_OVERRIDE` env stubs).
- Live stdin-JSON path verified with a real PostToolUse payload shape.
- Mirror sync verified byte-identical via `diff -q` (hook + git.md); `settings.json.template` validated as JSON; live `~/.claude/settings.json` wired idempotently.
- harness-hygiene: hook grep'd against the denylist — zero personal identifiers.

## Walking Skeleton
The thinnest end-to-end slice IS the self-test: a synthetic accounts.config + a synthetic wrong-account 404 payload → the hint text containing `gh auth switch -u <owner>`. C1 of the self-test is that slice; the live stdin-JSON verification confirms the same path through the real PostToolUse JSON contract.

## Decisions Log
### Decision: one hook, two entry points (L1 default + L2 --session-start)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** co-locate L1 (PostToolUse hint) and L2 (SessionStart account-map broadcast) in one file with a `--session-start` flag, rather than threading L2 into the unreadable inline switcher command string.
- **Alternatives:** edit the inline SessionStart switcher command string (fragile, untestable); a separate L2 script (more files, same concern split across two).
- **Reasoning:** one testable file for the account-blindness concern; one `--self-test` covers both layers. The L2 line is wired right after the existing switcher, so it still "extends the active-account broadcast" surface.
- **Checkpoint:** N/A
- **To reverse:** delete the hook, remove the two settings.json wirings + the git.md line + the harness-architecture row.

### Decision: owner==gh_user mapping with optional owners[] forward-compat
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** resolve owner→account by `gh_user==owner` (personal repos) OR membership in an optional `owners[]` array (org repos), case-insensitive.
- **Alternatives:** owner==gh_user only (misses org repos); hardcode org→account map (violates harness-hygiene).
- **Reasoning:** matches the documented config shape, stays identifier-free, and is forward-compatible if the real config later adds `owners[]` for org repos.
- **Checkpoint:** N/A
- **To reverse:** drop the `owners[]` branch in `_account_for_owner`.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): swept, all four behavior surfaces (L1 hook, L2 broadcast, L3 rule, doc row) cited in both Tasks and Files to Modify.
- S2 (Existing-Code-Claim Verification): swept — verified `read-local-config.sh` flatten pattern `[.work[]?,.personal[]?]`, the example config `gh_user` shape, and `gh auth status` active-account line format against the live tools.
- S3 (Cross-Section Consistency): swept, 0 contradictions (advisory/never-blocks claim consistent across Goal/Scope/Edge Cases).
- S4 (Numeric-Parameter Sweep): swept — only numeric is "9 self-test scenarios", consistent across plan, hook, and doc row.
- S5 (Scope-vs-Analysis Check): swept — every "Add/Build/Wire" verb targets a file in `## Files to Modify/Create`; nothing prescribed for a Scope-OUT file.

## Definition of Done
- [ ] All tasks checked off
- [ ] `--self-test` 9/9 green
- [ ] Live mirror byte-identical (diff -q) for hook + rule; settings.json wired
- [ ] harness-architecture.md row present
- [ ] SCRATCHPAD.md updated; Completion report appended; Status: COMPLETED

## Completion Report

_Generated by close-plan.sh on 2026-06-05T17:51:16Z._

### 1. Implementation Summary

Plan: `docs/plans/gh-account-blindness-mechanism.md` (slug: `gh-account-blindness-mechanism`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/gh-account-blindness-hint.sh`
- `adapters/claude-code/rules/git.md`
- `adapters/claude-code/settings.json.template`
- `docs/harness-architecture.md`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
07691d5 feat(conv-tree): Claude-side event emitter — Dispatch conversations auto-populate the GUI
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0d6bc43 feat(scope-gate): full-skip scope check during rebase/merge conflict resolution (#26)
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
14c4dfc feat(hook): session-start-git-freshness — fetch + behind + WIP-branch warns (#46)
15496c3 feat(rules+hook): branch-hygiene + stale-local-branch surfacer (#49)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1900089 feat(harness): static-trace.sh — auto-detect chain tracer for modified files
19a7ab7 Component B reconciler v1 — orchestrator wake-trigger + reconcile loop (single-machine, surface-first) (#58)
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1e6310c feat(hook): A7 — imperative-evidence linker
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2590947 feat(hook): pre-push-divergence-check — block stale-fetch pushes to master (#47)
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2dc69a5 feat(drift-detection): 3-component harness-internal cross-repo drift detection (#34)
331e048 feat(hooks): session-start cheatsheet + credential-asking guard (hygiene-2 PR 2/3) (#54)
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3a2babc reconverge: land personal fork onto PT master (decision-context + pr-health + F7 + principles)
3afa037 feat(phase-1d-c-3): Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension
3b19478 feat(hooks): cross-repo-drift-postpush-gate — surface NL remote divergence at push time
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
