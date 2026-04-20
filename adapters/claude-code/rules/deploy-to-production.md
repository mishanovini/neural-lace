# Deploy to Production — Default Behavior

## The rule

**Always deploy to production unless the user explicitly asks for a preview or staging target.** Previews are not a destination — they're a staging ground for tests that the agent runs. After the agent finishes its tests, the work should land on master and deploy to production.

## Why

The user has stated repeatedly that they do not use Vercel preview URLs to test. They test in production. Leaving work on a feature branch, telling them "here's the preview URL," and waiting for them to merge is wasted latency — they'll have to remind the agent to actually merge. This directive removes the friction.

**Documented in user's feedback memory** (`feedback_full_auto_deploy.md`): "Always full-auto mode; always deploy immediately after building; never wait for manual merge/review gates."

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

This is a Pattern rule, not hook-backed. The user's memory and this rule carry it. The behavioral signal: if the agent finishes testing and says "PR is ready for you to merge," the agent has violated this rule. The correct action is to merge it.

## Scope

Applies to: all project work where the target deploy is master → production (typical Vercel/Next.js setup). Any project where Vercel or similar auto-deploys on master merge falls under this rule.
