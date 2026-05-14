# Deploy to Production — Default Behavior

## The rule

**Always deploy to production unless the user explicitly asks for a preview or staging target.** Previews are not a destination — they're a staging ground for tests that the agent runs. After the agent finishes its tests, the work should land on master and deploy to production.

## Why

The user has stated repeatedly that they do not use Vercel preview URLs to test. They test in production. Leaving work on a feature branch, telling them "here's the preview URL," and waiting for them to merge is wasted latency — they'll have to remind the agent to actually merge. This directive removes the friction.

**Mechanism:** the per-project `automation-mode.json` config. Projects opt into `mode: full-auto` (auto-approve deploy-class Bash commands) or `mode: review-before-deploy` (pause for human authorization). Resolution order: `<project>/.claude/automation-mode.json` (per-project override) → `~/.claude/local/automation-mode.config.json` (user-global) → hardcoded fallback (`review-before-deploy`). The `automation-mode-gate.sh` PreToolUse Bash hook reads the effective mode and blocks/passes deploy commands accordingly. Switch via `/automation-mode <full-auto|review> [--project]`.

Pre-customer projects (no real users) typically run `mode: full-auto`. Once a project crosses the customer-tier boundary, flip back to `review-before-deploy` (or delete the per-project file to inherit the user-global default).

## What this means in practice

When a feature branch is green (tests pass locally against the live dev server + Supabase, typecheck passes, commits are clean):

1. **Push the branch** (if not already pushed)
2. **Open or update the PR** with a clear description
3. **Merge to master** — use `gh pr merge <N> --squash` or `--merge` as the project convention dictates
4. **Confirm the Vercel production deploy** succeeded by checking `gh pr checks` or the Vercel dashboard
5. **Report the production URL** to the user, not the preview URL

Do NOT wait for the user to say "now merge it." They have already said it. Every time.

## When to NOT auto-deploy

- The user says "preview only" or "don't merge yet"
- The work is a work-in-progress draft that the user explicitly wants to review first
- Tests are failing and the agent hasn't fixed them yet — never ship red
- Migrations have irreversible data effects that warrant a manual review step — surface this to the user and ask

## Stacked PRs

If PR B is stacked on PR A (B targets A's branch), merge A first, then rebase/retarget B to master, then merge B. Both land on master. Both deploy to production.

## Confirmation signal

After merging, the user should receive:
- The master deploy URL (production) — NOT the preview URL
- A clear summary of what merged and what is now live in production
- A note on any migrations that were applied (which happens on merge via our migration pipeline, or was already applied manually)

## Enforcement

**Hybrid.** The "default to deploy" Pattern is documented in this rule (the agent self-applies). The mechanical layer is `automation-mode-gate.sh` (PreToolUse Bash) — when the effective mode is `full-auto`, deploy-class commands (`git push`, `gh pr merge`, `vercel deploy`, etc.) pass through without per-action authorization; when the effective mode is `review-before-deploy`, those commands BLOCK with a review prompt. Per-project config at `<project>/.claude/automation-mode.json` overrides user-global at `~/.claude/local/automation-mode.config.json`. The behavioral signal: if the agent finishes testing in a `full-auto` project and says "PR is ready for you to merge," the agent has violated this rule. The correct action is to merge it.

## Scope

Applies to: all project work where the target deploy is master → production (typical Vercel/Next.js setup). Any project where Vercel or similar auto-deploys on master merge falls under this rule.
