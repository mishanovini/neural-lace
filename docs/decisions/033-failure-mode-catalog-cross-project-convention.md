# Decision 033 — Failure-Mode catalog is a cross-project convention on the existing canonical schema (additively extended)

- **Date:** 2026-05-19
- **Status:** Active
- **Stakeholders:** harness maintainer; every Claude Code session in any project that runs an investigation; the `harness-lesson` / `why-slipped` skills; the PR-template mechanism gate; every downstream project that consumes the harness.

## Context

A recent investigation took roughly twelve hours and several wrong leads to identify a framework + platform cold-init deadlock. If a Failure-Mode (FM) catalog had existed and been the *first* lookup, recognition could plausibly have happened in the first hour. The maintainer's directive: bake the FM-catalog pattern into the harness so it applies to **every** project uniformly, not per-project ad-hoc.

The harness already has a deeply-wired FM catalog at `docs/failure-modes.md`:

- Single file, **six-field schema**: `ID` / `Symptom` / `Root cause` / `Detection` / `Prevention` / `Example`.
- 23 entries (FM-001..FM-023) as of this decision.
- Consumed by ~40 files: `rules/diagnosis.md` ("After Every Failure: Encode the Fix"), the `harness-lesson` and `why-slipped` skills (both have an explicit "Step 0 — check the failure-mode catalog FIRST"), the PR-template "What mechanism would have caught this?" CI gate (answer forms reference `FM-NNN` IDs), 6+ rules, 8+ ADRs.

The originating brief proposed a *new* `docs/failure-modes/` **directory** with a *different* schema (`symptoms` / `discriminator` / `root cause` / `recovery` / `prevention` / `discovered`). Building that as literally specified would **fork the canonical catalog**: a file-vs-directory path collision (`docs/failure-modes.md` vs `docs/failure-modes/`), two competing schemas, and broken consumers (the skills and PR-gate grep `docs/failure-modes.md`). Catalog fragmentation is the exact failure an FM catalog exists to prevent — one catalog per project, one mechanism per class.

Two parts of the proposed schema are nonetheless genuinely valuable and absent from the existing one:

- **Discriminator** — how to tell *this* FM apart from look-alike FMs. The existing `Symptom` field is search-by-phenotype; it does not say "if X also looks like this, here is the distinguishing observation." A twelve-hour investigation is exactly the case where multiple FMs share surface symptoms and the discriminator is what shortcuts the dead ends.
- **Recovery** — the immediate steps to get *unstuck right now*. The existing `Detection`/`Prevention` fields are mechanism-facing (which hook/agent catches or stops the class). An investigator mid-incident needs the *human* unstuck path, which Detection/Prevention do not provide.

A second gap: the catalog is currently consumed at *encode* time (`diagnosis.md` "After Every Failure", the two skills' Step 0 when *proposing a mechanism*). Nothing instructs an investigation-class session to grep the catalog *before forming its first hypothesis*. The originating pain was a *diagnosis* that should have started at the catalog, not an *encoding* that should have checked it.

## Decision

1. **The canonical FM catalog convention is `docs/failure-modes.md` — a single file per project — with the existing six-field schema.** This is now a documented *cross-project* standard (`docs/conventions/failure-mode-catalogs.md`), adopted uniformly by the harness repo and every downstream project, not a per-project ad-hoc artifact. The forked-directory alternative is rejected.

2. **The schema is extended with two *optional, additive* fields** appended after `Example`: **`Discriminator`** and **`Recovery`**. Optional + additive = backward-compatible: every existing consumer reads by `Symptom` phenotype or by `FM-NNN` ID, never positionally by a fixed field count, so the 23 existing entries need no migration and continue to validate. New entries SHOULD populate both when they add signal; entries where they add nothing may omit them.

3. **An investigation-first reflex is added to `rules/diagnosis.md`**: before forming any hypothesis in an investigation/debug/root-cause session, grep the project's `docs/failure-modes.md` `Symptom`/`Discriminator` fields for keywords from the reported problem. This makes the catalog the first lookup in the diagnosis workflow, not only the last step of the encode workflow.

4. **Harness auto-search at session spawn is *proposed*, not shipped here** (`docs/proposals/fm-catalog-auto-search-harness-integration.md`). It is the highest-leverage piece (reflexive use without relying on agent memory) but is a separate execution.

5. **Per-project adoption** is delivered via a copy-able template skeleton (`docs/templates/project-failure-modes/`) and a documented bootstrap procedure in the convention doc; specific downstream-repo names are kept out of committed harness files per `harness-hygiene.md` and live only in the (non-committed) bootstrap task chips.

## Alternatives Considered

- **Build the requested `docs/failure-modes/` directory + new schema verbatim.** Rejected: forks the canonical catalog, collides on the `docs/failure-modes` path, breaks `harness-lesson` / `why-slipped` / the PR-template gate, and violates the harness's own one-catalog-per-project anti-fragmentation principle. The valuable parts of the proposed schema (Discriminator, Recovery) are captured additively instead.
- **Full schema replacement + migrate all 23 entries to the new six fields.** Rejected: large, churny, partially-irreversible rewrite of a load-bearing artifact for zero functional gain over the additive approach; every consumer would need re-validation.
- **Keep the catalog exactly as-is, add only the convention doc.** Rejected as insufficient: it would not deliver the investigation-first value (Discriminator/Recovery) that motivated the brief; the twelve-hour incident is precisely the gap those two fields close.

## Consequences

- **Enables:** one uniform FM-catalog convention across all projects; investigation sessions that start at the catalog; richer entries (Discriminator/Recovery) that shortcut look-alike dead-ends; a clean substrate for the proposed auto-search hook.
- **Costs:** the schema preamble grows by two optional fields; convention/template/proposal docs add maintenance surface; downstream projects must each adopt (mitigated by the copy-able skeleton + bootstrap procedure).
- **Blocks/risks:** a consumer that hard-codes the literal six-field list could in principle mishandle the two new fields — mitigated structurally by appending them after `Example` and marking them optional in the preamble; no shipped consumer parses positionally. Reversible via a single `git revert` of the ADR + convention + schema-preamble commits (the 23 original entries are untouched).
- **Cross-references:** `docs/conventions/failure-mode-catalogs.md` (the standard), `docs/failure-modes.md` (canonical instance), `docs/templates/project-failure-modes/` (adoption skeleton), `docs/proposals/fm-catalog-auto-search-harness-integration.md` (next execution), `adapters/claude-code/rules/diagnosis.md` (investigation-first reflex), Decision 008 (`docs/decisions/008-capture-codify-failure-modes-stub.md`, the original catalog stub this convention generalizes).
