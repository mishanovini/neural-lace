---
title: Default git push policy shifts from ask-before-push to auto-push
date: 2026-05-03
type: process
status: decided
auto_applied: true
originating_context: User directive 2026-05-03 during the discovery-protocol implementation session
decision_needed: n/a — auto-applied per user directive
predicted_downstream:
  - ~/.claude/rules/git.md (the rule itself)
  - adapters/claude-code/rules/git.md (mirror)
  - docs/decisions/013-default-push-policy.md (decision record)
  - docs/DECISIONS.md (index entry)
  - All future autonomous workflows that include git push as a natural step
---

# Default git push policy shifts from ask-before-push to auto-push

## What was discovered

The pre-existing rule "Do not push to git without asking" in `~/.claude/rules/git.md` line 5 added friction to every push without proportionate safety benefit at the harness's current maturity. Mechanical gates (`pre-push-scan.sh` for credential leaks, PreToolUse Bash hooks blocking `--no-verify`, force-push to master, public-repo creation under work-account directories) already cover the high-risk cases. The rule was earning less than its friction cost — the user repeatedly authorized pushes per-action, and the resulting "trail-off and wait for permission" pattern was a documented failure mode that `narrate-and-wait-gate.sh` was catching.

The user surfaced this directly during the 2026-05-03 session: "I'm thinking we need to get rid of the git.md rule 'Do not push to git without asking'. I actually want you to always push to git when appropriate."

## Why it matters

The friction cost was real. Across the multi-hour autonomous-delivery effort that produced commits cc20cde, 18d3911, b7ceb2d, ea76726 on `build-doctrine-integration`, the per-push pause-and-confirm pattern would have meant 4+ explicit user approvals for routine integration-branch pushes that carried no novel risk. The user's autonomous-delivery directive had ALREADY granted blanket push permission ("I'm giving you permission now to push all updates to GitHub for the remainder of all these efforts"); the harness rule still surfaced ambiguity because the rule said the OPPOSITE.

Removing the rule and replacing it with a positive default + safe-methods constraint + customer-tier conditional is the structurally clean answer. The customer-tier conditional preserves safety where it matters: real users introduce risk that the maintainer-only-cost calculation doesn't apply to.

## Options considered

- **Keep the existing rule.** Rejected. Friction cost > safety benefit at current maturity; mechanical gates handle the actual risk classes.
- **Drop all push restrictions entirely.** Rejected. Real-user projects need a different posture; mechanical safety gates remain in force.
- **Two-phase policy: auto-push pre-customer, branch-and-validate post-customer.** Chosen. Matches user's stated intent ("once we have real users, we'll need to have it always push to a dev or preview branch") with minimal new tooling.

## Recommendation

Replace the "do not push" line with: (a) positive default to push at natural completion points using safe methods, (b) explicit safe-methods enumeration (no force-push, no `--no-verify`, no `--no-gpg-sign`, honor branch protection), (c) customer-tier conditional (pre-customer = master is fine; real-user = dev/preview branch flow required). Per-project customer-tier judgment for now; mechanical auto-detection deferred until evidence justifies.

## Decision

Recommendation applied. Two files updated (rule + adapter mirror). Decision record at `docs/decisions/013-default-push-policy.md`. Index entry added to `docs/DECISIONS.md`.

## Implementation log

- `~/.claude/rules/git.md` — removed "Do not push to git without asking"; added 3 new bullets covering positive-default + safe-methods + customer-tier policy.
- `adapters/claude-code/rules/git.md` — mirrored.
- `docs/decisions/013-default-push-policy.md` — created with full Context / Decision / Alternatives / Consequences.
- `docs/DECISIONS.md` — index entry 013 added.
- This discovery file at `docs/discoveries/2026-05-03-default-push-policy-shifted-to-auto.md`.
- All changes ship in a single thematic commit on `build-doctrine-integration`.
- Per the new policy, this commit will be pushed without asking.
