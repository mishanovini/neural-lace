---
name: close-plan
description: Walk the orchestrator through plan closure mechanically. Validates which `plan-closure-validator.sh` checks currently pass, surfaces unmet gaps with specific actions (invoke task-verifier on Task N, populate Implementation Summary, reconcile backlog item, refresh SCRATCHPAD), writes the Completion Report from `~/.claude/templates/completion-report.md`, updates SCRATCHPAD + backlog, then flips `Status: ACTIVE → COMPLETED` (which triggers the closure-validator gate plus the auto-archive). Use whenever a plan's build work is finished and ready to close out — makes the right path easier than the wrong one.
---

# close-plan

Plan-closure mechanical assistant. Pairs with `plan-closure-validator.sh` (the PreToolUse gate) so closure work happens BEFORE the irreversible `Status: ACTIVE → COMPLETED` flip rather than being remembered "later."

## When to use

Invoke `/close-plan <slug>` when:

- A plan's build work has shipped (last task task-verifier-flipped to `[x]`)
- You're about to flip `Status: COMPLETED` and want closure work done atomically
- `plan-closure-validator.sh` blocked a Status flip and you need to address each unmet check
- The user says "close out the plan" or "wrap up plan X" or "mark plan complete"

## How to invoke

- With argument: `/close-plan <slug>` — operate on `docs/plans/<slug>.md`. The slug is the plan's basename (without `.md`).
- Without argument: read SCRATCHPAD.md's "Active Plan" pointer; if exactly one ACTIVE plan exists in `docs/plans/`, operate on it. Otherwise ask the user which plan to close.

## What this skill does (in order)

The five mechanical closure checks the validator runs are exactly the five steps the skill walks through. The skill surfaces gaps; you fix them; the skill flips Status when all gaps are closed.

### Step 1. Open the plan and inventory

Read the plan file. Extract:

- Slug (basename minus `.md`)
- `Status:` (must be `ACTIVE`; if not, refuse with a message — DEFERRED/ABANDONED don't need this skill)
- `Backlog items absorbed:` value (may be `none` — that's fine)
- All task IDs from the `## Tasks` section
- Existing `## Evidence Log` content + sibling `<slug>-evidence.md` if present

### Step 2. Check (a) — every task checkbox flipped

Scan `## Tasks` for any `- [ ]` lines. For each:

- Surface it: "Task N has not been task-verifier-flipped. Invoke task-verifier on Task N now."
- DO NOT flip it yourself (only `task-verifier` may flip; see `~/.claude/rules/planning.md` Verifier Mandate).

If there are unchecked tasks, dispatch `task-verifier` on each in sequence (one per task). After each PASS the verifier flips the checkbox + writes the evidence block. Loop until zero `- [ ]` remain or until any verifier returns FAIL.

If a task can't pass verification, STOP — the plan should not be closed. Surface which task is stuck and let the user decide whether to defer the plan or fix the task.

### Step 3. Check (b) — every task has a PASS evidence block

For each task ID, search:

1. The sibling `<slug>-evidence.md` for `Task ID: <id>` + `Verdict: PASS` in the same block.
2. The plan's `## Evidence Log` section for the same.

If a task lacks PASS evidence, the verifier in step 2 should have written it. If still missing, re-invoke task-verifier on that task ID. Substantive evidence reviews live in `plan-evidence-reviewer` — the gate only checks structural presence + PASS.

### Step 4. Check (c) — write the Completion Report

Read `~/.claude/templates/completion-report.md`. Populate the `## Completion Report` section of the plan file with all six template subsections:

- **Implementation Summary** — map each task to what shipped. Include commit SHAs for each task. The skill can pre-fill SHAs by reading `git log --grep="Task <id>"` or by listing recent commits on the feature branch; orchestrator confirms.
- **Design Decisions & Plan Deviations** — copy from the plan's `## Decisions Log` and the `## In-flight scope updates` section if any entries exist; flag any Tier 2+ decision that lacks a `docs/decisions/NNN-*.md` record.
- **Known Issues & Gotchas** — orchestrator-provided. The skill prompts: "Any limitations, technical debt, edge cases discovered during build that future maintainers should know about?"
- **Manual Steps Required** — orchestrator-provided. The skill prompts: "Anything the user needs to do that the harness cannot — env vars, deploys, third-party setup?"
- **Testing Performed & Recommended** — read the plan's `## Testing Strategy` and the evidence blocks; summarize what was actually verified.
- **Cost Estimates** — orchestrator-provided. Skip with "n/a" if the plan introduces no recurring cost (typical for harness-development plans).

If `Backlog items absorbed:` is non-empty, the Implementation Summary MUST list each absorbed item with its shipped status (built with commit SHA, deferred with reason, abandoned with reason). Per `~/.claude/rules/planning.md`, items marked built archive inside the plan; items marked deferred/abandoned return to `docs/backlog.md`.

Apply the populated `## Completion Report` to the plan file via a single `Edit` call (replacing whatever exists between `## Completion Report` and the next `## ` heading or end-of-file).

### Step 5. Check (d) — reconcile docs/backlog.md

If `Backlog items absorbed:` is `none` or missing, skip this step.

Otherwise, for each absorbed slug:

- Find the slug in `docs/backlog.md`. It should currently sit under an open section (e.g., `## Open work`).
- Decide its disposition:
  - **Built** → move the entry under a heading containing "Recently implemented", "Completed", "Resolved", or "ABSORBED" (use whichever convention the project's backlog already uses; default to a top-level `## Recently implemented (YYYY-MM-DD)` heading if none exists). Add a one-line `(absorbed into <plan-path>; commit <SHA>)` marker.
  - **Deferred / abandoned** → add a `(deferred from <plan-path>)` or `(abandoned from <plan-path>)` marker; the entry returns to the open section so a future plan can pick it up.
- Update `Last updated: YYYY-MM-DD` on line 2 of the backlog.

The validator's check (d) accepts an entry as reconciled when the slug appears under a closed-section heading OR has a `(deferred from ` / `ABSORBED` marker on its line.

### Step 6. Check (e) — refresh SCRATCHPAD.md

Update `SCRATCHPAD.md` at the repo root:

- `## Latest Milestone` — rewrite to name the closed plan and the date
- `## Active Plan` — flip from `<plan-path>. Status: ACTIVE` to `None` (or to the next active plan if one exists)
- `## What's Next` — clear items the closing plan completed; surface follow-up backlog items if any
- Reference the plan slug somewhere in the body (the validator checks for slug presence)

Ensure the file's mtime updates (Edit/Write naturally does this). The validator requires mtime within 60 minutes — closing in the same session always satisfies this.

### Step 7. Flip Status: ACTIVE → COMPLETED

This is the irreversible step. Apply a single `Edit` call to the plan file's header changing `Status: ACTIVE` to `Status: COMPLETED`. Three things happen:

1. **PreToolUse:** `plan-closure-validator.sh` runs — re-validates all five checks.
2. **If gate ALLOWS:** the Edit applies; PostToolUse `plan-lifecycle.sh` fires and `git mv`s the plan + sibling `<slug>-evidence.md` into `docs/plans/archive/`.
3. **If gate BLOCKS:** stop. The stderr names which check failed; loop back to that step.

### Step 8. Commit

`git add` the plan-closure changes (plan file moved to archive, completion report content, backlog updates, SCRATCHPAD update) and commit with a message of the form:

```
plan(<slug>): close — Status COMPLETED, archived

Closure work:
- Completion Report populated
- Backlog items <list> reconciled
- SCRATCHPAD updated
```

### Step 9. Offer to push

Per `~/.claude/rules/git.md` "default is to push, not to wait." Offer: "Closure committed locally on <branch>. Push to origin now?" — wait for user's yes/no. Do not push automatically (a closing commit is the kind of milestone the user may want to review first), but make pushing easy.

## Counter-incentives this skill resists

The orchestrator's bias is to flip `Status: COMPLETED` first and worry about closure work later. The validator now blocks this. The skill's job is to make the right path (closure work first, then flip) the path of least resistance — single command, walks through every check, surfaces every gap, ends with the Status flip + commit + offer-to-push.

If the orchestrator finds itself trying to bypass the gate (`git commit --no-verify`, manually `git mv`-ing the plan to archive, editing the validator hook to skip a check), STOP. The gate exists because the originating 2026-05-05 stranding incident — a plan ACTIVE for two days with all 5 task checkboxes empty despite all 5 tasks shipped — was caused by exactly that "I'll come back to bookkeeping later" deferral. Closure work is part of the build, not a follow-up.

## Cross-references

- `adapters/claude-code/hooks/plan-closure-validator.sh` — the PreToolUse gate this skill pairs with
- `adapters/claude-code/hooks/plan-lifecycle.sh` — the PostToolUse hook that auto-archives once the gate allows
- `~/.claude/templates/completion-report.md` — the template Step 4 reads
- `~/.claude/rules/planning.md` — Verifier Mandate, plan-file lifecycle, backlog absorption rules
- `~/.claude/rules/vaporware-prevention.md` — enforcement-map row for closure-validation
- `docs/plans/harness-gap-16-closure-validation.md` — the originating plan
