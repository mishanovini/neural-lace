# Decision 002: Attribution-only anonymization policy

**Date:** 2026-04-18
**Status:** Active
**Tier:** 2
**Stakeholders:** Misha (maintainer)

## Context

During scrub of harness files, every reference to personal name, business org, product codename, or past-project context must be classified as either "ship" or "scrub." The audit found 30+ such references across rules, docs, hooks, and agents.

## Decision

**Keep attribution-only.** Preserve the maintainer's first name (`**Owner:** Misha` in strategy doc, README) as professional attribution. Strip everything else:

- All business/org names (Pocket-Technician, pt-leads, pocket-technician-*)
- All product codenames (Circuit, Foresight)
- All incident-specific details tied to real products ("HVAC contractor lead management", "personal finance", "the impersonation bug on 12 dashboards", specific feature names like `simulate-turn` / `A5d hold-for-review`)
- All OneDrive / Windows-user / home-directory paths containing a username
- All GitHub username hardcoding (mishanovini, MishaPT)

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
