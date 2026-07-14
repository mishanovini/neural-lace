# Plan: Needs-from-you two-bucket sign-off — kill the "false nothing"

Status: ACTIVE
Mode: code
lifecycle-schema: v2
acceptance-exempt: true  # harness-internal rule + lesson; no user-facing product surface
Backlog items absorbed: none

## Goal
Close the §1 honesty hole the operator caught 2026-07-13: a session signed off "Needs from
you: nothing" in the same message that delivered admin-shell commands the operator had to
run. Root cause — the constitution §2 single-slot sign-off conflated "am I blocked?" with
"is any action expected of you?", so non-blocking-but-real asks vanished as "nothing". Fix
= split the sign-off into two explicit buckets (Blocking / When-you-can) in the always-loaded
rule, and record the lesson.

## Files to Modify/Create
- `adapters/claude-code/rules/constitution.md` — §2 sign-off rule rewritten to the two-bucket split.
- `docs/lessons/2026-07-13-false-nothing-needed-from-you.md` — the lesson (new).
- `docs/plans/needs-from-you-two-bucket-signoff-2026-07-13.md` — this plan.

## Tasks
- [ ] 1. Rewrite constitution §2 sign-off to Blocking / When-you-can + name the "false nothing" a §1 violation; write the lesson; route through harness-reviewer; address findings. Verification: mechanical

## Closure Contract
- **Commands that run:** `git show --stat HEAD` confirms both files landed; `wc -c adapters/claude-code/rules/constitution.md` is under the 24000B cap; `grep -c 'When you can' adapters/claude-code/rules/constitution.md` ≥ 1.
- **Expected outputs:** constitution contains the two-bucket sign-off (Blocking + When you can), byte size < 24000, harness-reviewer verdict recorded as CONDITIONAL-PASS with its Major finding fixed.
- **On-disk artifact location:** `adapters/claude-code/rules/constitution.md` §2 + `docs/lessons/2026-07-13-false-nothing-needed-from-you.md`; evidence in this plan's `## Evidence Log`.
- **Done when:** the two-bucket sign-off is on master (both remotes) and live-synced to `~/.claude/rules/constitution.md`.

## Evidence Log
- Task 1: harness-reviewer CONDITIONAL-PASS (Pattern-class); the one Major (inverted/nonexistent
  `NEEDS-YOU.md` cross-reference in the first draft) + two Minors (FYI carve-out, Blocking↔§6 link)
  all applied before commit. Constitution 11136B (< 24000 cap). Warn-mode Stop-lint deferred to an
  nl-issue with the reviewer's FP caveat. commit: 919fc30
