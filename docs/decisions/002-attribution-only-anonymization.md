# Decision 002: Attribution-only anonymization policy

**Date:** 2026-04-18
**Status:** Active
**Tier:** 2
**Stakeholders:** Maintainer

## Context

During scrub of harness files, every reference to personal name, business org, product codename, or past-project context must be classified as either "ship" or "scrub." The audit found 30+ such references across rules, docs, hooks, and agents.

## Decision

**Keep attribution-only.** Preserve the maintainer's first name (`**Owner:** <maintainer>` in strategy doc, README) as professional attribution. Strip everything else:

- All business/org names (`<work-org-codename>`, `<work-org-internal>`)
- All product codenames (`<product-codename-A>`, `<product-codename-B>`)
- All incident-specific details tied to real products (specific industry references, specific feature names)
- All cloud-storage / Windows-user / home-directory paths containing a username
- All GitHub username hardcoding (`<personal-account>`, `<work-org-account>`)

Anonymize technical incidents by replacing with generic language: "a production Next.js app", "a prior incident", "an impersonation bug" (no product name).

## Alternatives Considered

- **Full anonymization** (no attribution) — rejected: maintainer attribution is professional norm; adds zero risk.
- **Keep product-type context** ("built while working on a CRM and personal-finance app") — rejected: adds maximum identity footprint for zero utility; readers don't need to know what products motivated each rule.

## Consequences

- **Enables:** public release with bounded identity disclosure; technical lessons in rule files survive intact.
- **Costs:** some rule files lose color (incident-specific examples become generic); future contributors cannot easily trace "why this rule exists" to a specific incident.
- **Mitigation for the cost:** decision records like this one preserve the reasoning for the maintainer; private archive preserves full history.

## Implementation reference

Phase 4 of `docs/plans/public-release-hardening.md`.
