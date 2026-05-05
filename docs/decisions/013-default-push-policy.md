# Decision 013 — Default git push policy: auto-push (safe methods); customer-tier branching for real-user projects

**Date:** 2026-05-03
**Status:** Active
**Stakeholders:** Maintainer

## Context

The pre-existing rule in `~/.claude/rules/git.md` was: "Do not push to git without asking." This was a sensible conservative default early in harness development, when the cost of any push was potentially high and the harness's gates were less mature. The user has now lifted this constraint with a clear two-phase policy.

The current state of pushes in the harness:

- **Mechanical gates protect against unsafe pushes:** `pre-push-scan.sh` blocks credential leaks before push reaches GitHub; PreToolUse Bash hooks block `--no-verify`, force-push to master, public-repo creation under work-account directories.
- **The `Do not push without asking` rule was prose-only** — it could be (and frequently was) waived per-action by the user saying "go ahead."
- **The user's project mix:** all currently-active projects (across work-org and personal codename suites, plus Neural Lace itself) are pre-customer. There are no real users whose data could be impacted by a bad push to production.

## Decision

Replace the "Do not push to git without asking" rule with a two-part policy:

1. **Default: push when work reaches natural completion point.** Feature branch ready for review, atomic commit verified, plan task task-verified PASS. Push without asking. Use safe methods only — no force-push to protected branches, no `--no-verify`, no `--no-gpg-sign`. Honor branch protection.

2. **Customer-tier branching policy:**
   - **Pre-customer projects** (no real users yet): merging to master that deploys to production is acceptable. The cost of a bad push is mostly self-inflicted and reversible via revert + redeploy.
   - **Real-user projects**: all work must go through a `dev` or `preview` branch with deployment-validation gates before merge to the customer-facing branch.

Mechanical enforcement of customer-tier is deferred — per-project judgment for now; a future hook may auto-detect from project metadata.

## Alternatives considered

- **Keep the existing rule.** Rejected because it adds friction to every push without proportionate safety benefit at the harness's current maturity. Mechanical gates already cover the high-risk cases (credentials, force-push, public-repo). The rule was earning less than its friction cost.

- **Drop all push restrictions.** Rejected because real users introduce a class of risk the harness should respect. The customer-tier conditional preserves safety where it matters.

- **Auto-detect customer-tier from a config field.** Discussed; deferred. Adds tooling work upfront for limited present-day benefit (no project currently has real users). When a project crosses the threshold, the per-project judgment can be made; mechanical enforcement can be added if the failure mode appears.

## Consequences

**Enables:**
- Faster autonomous workflows — no per-push human check-in friction.
- Composes cleanly with the autonomous-delivery directive (auto-apply reversible decisions; pause for irreversible).
- Reduces the "trail-off and wait for permission to push" pattern that the narrate-and-wait gate has been catching.

**Costs:**
- A bad push to a pre-customer project's master is now possible without an explicit user check-in. Mitigation: `pre-push-scan.sh`, branch-protection (when configured), and the user's review of pushed-to-GitHub work after the fact.
- The customer-tier transition is a manual judgment call until mechanically enforced. Mitigation: when a project gets its first real user, the maintainer must remember to set up branch-protection + dev/preview branch flow before merging more work.

**Blocks:**
- Nothing structural. The existing safe-methods rules remain in force.

## Implementation

This commit:
1. Updated `~/.claude/rules/git.md` — replaced the "do not push" rule with the two-part policy
2. Mirrored to `adapters/claude-code/rules/git.md`
3. Added `docs/decisions/013-default-push-policy.md` (this file)
4. Added entry to `docs/DECISIONS.md` index
5. Captured as a discovery at `docs/discoveries/2026-05-03-default-push-policy-shifted-to-auto.md`

## Cross-references

- `~/.claude/rules/git.md` — updated rule
- `~/.claude/rules/security.md` — credential-handling rules unchanged
- `adapters/claude-code/hooks/pre-push-scan.sh` — credential-leak blocker (still active)
- Existing PreToolUse Bash hooks — `--no-verify` block, force-push block, public-repo block (still active)
- `~/.claude/rules/discovery-protocol.md` — this decision is captured as a discovery file with `Status: decided`, `auto_applied: true`, type `process`
