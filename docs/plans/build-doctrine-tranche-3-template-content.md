<!-- scaffold-created: 2026-05-06T08:15:00Z by start-plan.sh slug=build-doctrine-tranche-3-template-content -->
# Plan: Build Doctrine Tranche 3 Template Content
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan — templates are doctrine artifacts seeded for downstream-project consumption; no end-user product surface; validation is structural (file-exists + heading-shape + frontmatter sanity).
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal

Seed `build-doctrine-templates/` with default content for the 11 universal floors per `build-doctrine/doctrine/08-project-bootstrapping.md`, the 4 named-language naming conventions, branch-and-commit conventions, and one architectural-default worked example (API style). After this tranche lands, a downstream project bootstrapping per stage 0 has concrete, copy-and-customize templates for every universal floor at Express + Standard depths.

## Scope
- IN: 11 universal-floor templates × 2 depths (Express + Standard) at `build-doctrine-templates/conventions/universal-floors/<floor>/`. 4 language naming-convention defaults at `build-doctrine-templates/conventions/naming/<language>.md`. Branch-and-commit conventions at `build-doctrine-templates/conventions/branching-and-commits.md`. API-style architectural default at `build-doctrine-templates/conventions/architectural-defaults/api-style.md`. README at `build-doctrine-templates/conventions/README.md`. CHANGELOG entry recording v0.3.
- OUT: Deep depth content (deferred to Tranche 7 or post-pilot if friction surfaces). Architectural defaults beyond API-style (deferred per roadmap recommendation). UI-specific UX-standards expansion beyond the 11th floor template. Per-project bootstrap automation (Tranche 4 — pilot project work).

## Tasks

- [ ] 1. Author Floor 1 (Logging) Express + Standard templates. Verification: mechanical
- [ ] 2. Author Floor 2 (Error handling) Express + Standard templates. Verification: mechanical
- [ ] 3. Author Floor 3 (Secrets handling) Express + Standard templates. Verification: mechanical
- [ ] 4. Author Floor 4 (Input validation) Express + Standard templates. Verification: mechanical
- [ ] 5. Author Floor 5 (Auth and authorization) Express + Standard templates. Verification: mechanical
- [ ] 6. Author Floor 6 (Observability beyond logs) Express + Standard templates. Verification: mechanical
- [ ] 7. Author Floor 7 (Testing) Express + Standard templates. Verification: mechanical
- [ ] 8. Author Floor 8 (Documentation in code) Express + Standard templates. Verification: mechanical
- [ ] 9. Author Floor 9 (Dependency policy) Express + Standard templates. Verification: mechanical
- [ ] 10. Author Floor 10 (Versioning) Express + Standard templates. Verification: mechanical
- [ ] 11. Author Floor 11 (UX standards) Express + Standard templates. Verification: mechanical
- [ ] 12. Author 4 language naming-convention defaults (JavaScript/TypeScript, Python, Go, Rust). Verification: mechanical
- [ ] 13. Author branch-and-commit conventions. Verification: mechanical
- [ ] 14. Author API-style architectural default (worked example). Verification: mechanical
- [ ] 15. Author conventions README + update build-doctrine/CHANGELOG.md with v0.3 entry. Verification: mechanical

## Files to Modify/Create
- `build-doctrine-templates/conventions/universal-floors/01-logging/{express,standard}.md` — CREATE (Task 1)
- `build-doctrine-templates/conventions/universal-floors/02-error-handling/{express,standard}.md` — CREATE (Task 2)
- `build-doctrine-templates/conventions/universal-floors/03-secrets-handling/{express,standard}.md` — CREATE (Task 3)
- `build-doctrine-templates/conventions/universal-floors/04-input-validation/{express,standard}.md` — CREATE (Task 4)
- `build-doctrine-templates/conventions/universal-floors/05-auth-and-authorization/{express,standard}.md` — CREATE (Task 5)
- `build-doctrine-templates/conventions/universal-floors/06-observability-beyond-logs/{express,standard}.md` — CREATE (Task 6)
- `build-doctrine-templates/conventions/universal-floors/07-testing/{express,standard}.md` — CREATE (Task 7)
- `build-doctrine-templates/conventions/universal-floors/08-documentation-in-code/{express,standard}.md` — CREATE (Task 8)
- `build-doctrine-templates/conventions/universal-floors/09-dependency-policy/{express,standard}.md` — CREATE (Task 9)
- `build-doctrine-templates/conventions/universal-floors/10-versioning/{express,standard}.md` — CREATE (Task 10)
- `build-doctrine-templates/conventions/universal-floors/11-ux-standards/{express,standard}.md` — CREATE (Task 11)
- `build-doctrine-templates/conventions/naming/{javascript-typescript,python,go,rust}.md` — CREATE (Task 12)
- `build-doctrine-templates/conventions/branching-and-commits.md` — CREATE (Task 13)
- `build-doctrine-templates/conventions/architectural-defaults/api-style.md` — CREATE (Task 14)
- `build-doctrine-templates/conventions/README.md` — CREATE (Task 15)
- `build-doctrine/CHANGELOG.md` — MODIFY (Task 15)
- `docs/build-doctrine-roadmap.md` — MODIFY (Task 15)
- `docs/plans/build-doctrine-tranche-3-template-content.md` — CREATE (this plan)
- `docs/decisions/queued-build-doctrine-tranche-3-template-content.md` — CREATE (companion queue)

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The 11 universal floors and 4 named languages enumerated in `build-doctrine/doctrine/08-project-bootstrapping.md` are authoritative for v1; no new floors are introduced this tranche.
- Templates are short (Express ≈ 10-30 lines per floor; Standard ≈ 30-80 lines per floor). Concise + complete is preferred over encyclopedic.
- Express depth = silent default (one specific recommendation). Standard depth = surfaced default + 2-3 named alternatives with tradeoffs. Deep depth (deferred) = full alternatives matrix.
- Architectural defaults beyond API-style are intentionally not authored here — Tranches 4 and 7 will surface friction that informs which others are worth authoring.

## Edge Cases
- A floor's existing harness implementation (Floor 3 secrets, Floor 7 testing, Floor 11 UX) is more comprehensive than the template-default. Mitigation: templates point at harness rule files as the authoritative implementation.
- Naming-convention defaults differ across project-styles. Mitigation: templates state ONE default + name the alternative.
- The 11 universal floors may grow over time. Mitigation: this tranche ships v1; new floors are additive.

## Acceptance Scenarios

n/a — harness-development plan, no product user.

## Out-of-scope scenarios

None — harness-development plan, acceptance-exempt.

## Testing Strategy
- **File-exists checks:** every named output file exists with non-empty content.
- **Heading-shape check:** each Express/Standard template has at least one `## ` heading and a one-line tldr at top.
- **Cross-reference check:** the conventions README enumerates every floor + language file by name.
- **Per-task verification:** all 15 tasks use `Verification: mechanical`. Templates are prose; no contract-validation against schemas.

## Walking Skeleton

Walking Skeleton: n/a — pure content authoring. Floor 1 (Logging) is the simplest and authoring its Express + Standard templates first establishes the per-floor file shape that the other 10 mirror.

## Decisions Log

(populated during implementation per Mid-Build Decision Protocol)

## Definition of Done
- [ ] All 15 tasks checked off
- [ ] All 11 floors have Express + Standard templates (22 files)
- [ ] All 4 language naming defaults exist
- [ ] Branch-and-commit + API-style architectural-default exist
- [ ] Conventions README documents the layout
- [ ] build-doctrine/CHANGELOG.md updated with v0.3 entry
- [ ] docs/build-doctrine-roadmap.md Quick status table flipped: Tranche 3 → ✅ DONE
- [ ] Plan closed via close-plan.sh
