---
title: Configured SSH multi-push on neural-lace remotes; closed HARNESS-GAP-12
date: 2026-05-04
type: process
status: implemented
auto_applied: true
originating_context: D4 of the D1-D5 educational re-do session 2026-05-03; user confirmed option C 2026-05-04
decision_needed: n/a — auto-applied per user directive (option C confirmed)
predicted_downstream:
  - HARNESS-GAP-12 (now closed structurally)
  - All future neural-lace pushes (will go to both GitHub accounts atomically)
  - The auth-switch PreToolUse hook (now irrelevant for neural-lace pushes — SSH bypasses gh-active-account)
---

# Configured SSH multi-push on neural-lace remotes; closed HARNESS-GAP-12

## What was discovered

Pre-existing SSH state: BOTH GitHub accounts had SSH keys already configured at session start. `~/.ssh/id_ed25519_mn` (personal) and `~/.ssh/id_ed25519_pt` (work-org), with `~/.ssh/config` mapping `Host github.com` to the personal key and `Host github-pt` to the work-org key. SSH connection test confirmed authentication as the personal account.

Per user instruction (D4 of the 2026-05-04 dialogue): "If [SSH is] already there, then let's go with C." Implemented.

## Why it matters

HARNESS-GAP-12 was the recurring auth-switch failure on neural-lace pushes (3 occurrences in the same session, requiring manual `gh auth switch --user <personal-account>` + retry each time). The root cause: HTTPS auth via gh-credentials depends on the active gh account, and the auth-switch hook was switching to the wrong account based on imperfect directory pattern matching for a dual-hosted repo.

SSH auth resolves this entirely: each remote's URL specifies which Host pattern to use, and the SSH config maps each Host to a specific key. No gh dependency. The auth-switch hook becomes irrelevant for neural-lace pushes.

## Options considered

- **A** — Local config mapping fix only (B from prior analysis). Rejected: doesn't solve dual-sync.
- **B** — Multi-push without SSH (HTTPS only). Rejected: HTTPS auth still depends on gh-active-account; multi-push would fail on the URL whose account isn't active.
- **C** — Multi-push + SSH for both remotes. Selected.
- **D** — Post-push automation hook. Rejected: more moving parts; doesn't address root cause.

## Recommendation

C, applied.

## Decision

C applied. Configuration:

```bash
# Switched origin from HTTPS to SSH (uses Host github.com → personal key)
git remote set-url origin git@github.com:<personal-account>/neural-lace.git

# Added work-org URL as a second push URL on origin (multi-push)
git remote set-url --add --push origin git@github-pt:<work-org>/neural-lace.git
git remote set-url --add --push origin git@github.com:<personal-account>/neural-lace.git

# Switched pt remote from HTTPS to SSH (uses Host github-pt → work-org key)
git remote set-url pt git@github-pt:<work-org>/neural-lace.git
```

Result: `git push origin <branch>` now pushes to BOTH GitHub accounts atomically. Each URL auths via its own SSH key per the Host pattern. No gh-auth-switch dance.

## Implementation log

- `git remote -v` confirms multi-push: origin has fetch URL (personal SSH) + 2 push URLs (work-org SSH and personal SSH); pt has fetch+push URL (work-org SSH).
- Tested via `git push origin build-doctrine-integration`: pushed to BOTH remotes; both now at SHA `566ffa6`.
- Pushed recovery tag `pre-build-doctrine-integration` to work-org (was previously only on personal).
- HARNESS-GAP-12 status flipped to "implemented" in `docs/backlog.md`.
- The auth-switch hook still fires on `git push` invocations (it's wired in settings.json) but the switch-effect is harmless because SSH doesn't use gh credentials.

## Fallback for when multi-push fails

Per user requirement: "we also need a backup for when C ever fails."

With SSH multi-push, the fallback is automatic:
- If multi-push fails (e.g., one URL is unreachable), the push stops at the failing URL but the URL that succeeded still received the commit.
- To explicitly push to one remote: `git push pt <branch>` (uses pt remote, work-org SSH) OR `git push origin <branch>` (uses origin, multi-push).
- For an emergency single-remote push that bypasses multi-push entirely: `git push git@github.com:<personal-account>/neural-lace.git <branch>` (raw URL, single push).

The fallback works because SSH auth is per-key-per-Host, not per-active-gh-account. There's no auth-switch state to manage.

## Cross-references

- HARNESS-GAP-12 (now closed): `docs/backlog.md`
- Decision 013 (default git push policy): `docs/decisions/013-default-push-policy.md`
- The auth-switch hook in `settings.json.template` line ~99-106 is now harmless-but-redundant for neural-lace; could be tightened in a future cleanup.
