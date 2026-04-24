# Decision 006: CI workflow + local pre-push hook (both layers)

**Date:** 2026-04-23
**Status:** Implemented
**Tier:** 2
**Stakeholders:** Misha (maintainer)

## Context

Capture-codify enforcement could live in CI only (canonical, every PR must pass), local pre-push only (catches mistakes earlier but bypassable), or both. Each layer has overlap and adds maintenance cost.

## Decision

Ship both layers, with the CI workflow as canonical (branch protection requires its check) and the local pre-push hook as an opt-in convenience that catches the omission before the push reaches origin. Both share the same validator library at `.github/scripts/validate-pr-template.sh` so regex patterns and stderr messages cannot drift.

## Alternatives Considered

- **CI only** — rejected because the local hook saves a CI roundtrip when the omission is caught locally. A typical writer who forgets the field discovers it 30-60 seconds after pushing (when the CI check turns red); the local hook surfaces it instantly at push time. Local-only would also miss cases where the developer pushes from an environment without the hook installed.
- **Local hook only** — rejected because local hooks are bypassable (`--no-verify`) and not installed by default in fresh clones. CI is the canonical gate; the local hook is the first-pass convenience.
- **Single layer with smart placement** — there's no single layer that catches both forgetful-honest writers (local hook is best) AND adversarial-bypass attempts (CI is best). Two layers cost little and cover overlapping windows.

## Consequences

- **Enables:** instant feedback at push time for forgetful writers; canonical enforcement at PR time for everyone else; identical messages in both contexts (no "the local hook said one thing but CI said another").
- **Costs:** two install paths to maintain (the rollout script handles this); one shared library to keep in sync (mitigated by sourcing rather than copying).
- **Blocks:** none. The local hook is opt-in per repo via the rollout script.

## Implementation reference

`.github/workflows/pr-template-check.yml` (CI), `adapters/claude-code/git-hooks/pre-push-pr-template.sh` (local), shared library at `.github/scripts/validate-pr-template.sh`. Plan section 10, Decision 3.
