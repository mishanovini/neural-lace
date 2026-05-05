# Decision 023 — Definition-on-first-use enforcement

**Date:** 2026-05-04
**Status:** Active
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-f-definition-on-first-use.md` (Status: ACTIVE)
**Related backlog item:** HARNESS-GAP-10 sub-gap G (closed by this plan)

## Context

Sub-gap G of the audit batch (HARNESS-GAP-10): Build Doctrine + Neural Lace docs use ~50+ acronyms heavily. The user requested a glossary, which now lives at `~/claude-projects/Build Doctrine/outputs/glossary.md` (322 lines, 2026-05-03). The glossary is a single-source-of-truth for every acronym, term, and named concept used across the doctrine docs and the harness.

The remaining problem: nothing prevents new docs from introducing **undefined** acronyms. The glossary is necessary but not sufficient — without an enforcement mechanism, future docs accumulate undefined terms again, the same drift the glossary was meant to close.

The structural fix is a pre-commit gate that reads every staged `*.md` file under a configured scope-prefix (initially `neural-lace/build-doctrine/`), extracts new acronyms via a deterministic regex, and blocks the commit if any acronym is neither in the glossary nor defined in-context within the same diff.

This decision locks the five sub-decisions the gate depends on. Implementation lives in `adapters/claude-code/hooks/definition-on-first-use-gate.sh` (Phase 1d-F Task 2); rule documentation lives at `adapters/claude-code/rules/definition-on-first-use.md` (Phase 1d-F Task 1).

## Decision

The gate's behavior is defined by five sub-decisions:

### 023a — Acronym detection regex

Acronyms are detected via the regex `\b[A-Z]{2,6}\b`. The 2-character lower bound is required to avoid flooding noise from single capitalized words; the 6-character upper bound covers common acronyms (PRD, ADR, LLM, ITPM, HARNESS) without false-matching short uppercased proper nouns or all-caps titles. Mixed-case identifiers (camelCase, code symbols) are NOT flagged. Words longer than 6 characters in all-caps are NOT flagged (typically prose emphasis, not acronyms).

### 023b — Stopword allowlist

The following uppercase tokens are NEVER flagged, even when they match the regex. They are common English words, file-format names, or web-protocol names whose definition is universally understood:

```
OK OR AND IF IS OF BY IN ON AT TO THE A
WHO WHAT WHERE WHEN WHY HOW
JSON YAML TOML MD PDF PNG JPG GIF SVG XML CSV TSV
URL URI HTTP HTTPS FTP SSH TLS SSL DNS
API CLI GUI UI UX CSS HTML JS TS SQL
ID IDS IP CPU GPU RAM ROM USB DVD CD
PR PRS CI CD QA RC OS
```

The list is intentionally generous on the side of false-negatives. A term excluded from this list that should be flagged is added to the list later; a term mistakenly flagged that should not have been is added to the stopword list as the recovery.

### 023c — Scope-prefix

Initial scope is `neural-lace/build-doctrine/**/*.md` — the doctrine documents specifically. Other documentation paths (NL rules, ADRs, plans, README) are NOT in scope for v1 of the gate. The scope is configurable later via a per-machine config; the v1 hard-codes the scope-prefix to keep the implementation deterministic and auditable.

### 023d — "Defined" semantics

A term is considered "defined" if EITHER:

- **(a) It appears in the glossary** at any of these patterns (the gate checks all four):
  - `**TERM**` (the canonical glossary format — bold inline)
  - `## TERM` (heading format, future-proofing)
  - `### TERM` (sub-heading format)
  - `| TERM |` (table-cell format)

- **(b) It is defined in-context within the same diff via a parenthetical** within ~30 chars of the first occurrence (e.g., `LLM (large language model)` or `XYZ (foo bar baz)`). The gate uses the regex `<TERM>\s*\(.{2,40}\)` to detect this pattern. The parenthetical must contain at least 2 words to be recognized as a definition (single-word parentheticals are typically aliases, not definitions).

The "defined-in-diff" path lets authors introduce a one-off acronym without polluting the glossary; the "defined-in-glossary" path is the canonical home for terms used across more than one doc.

### 023e — Failure message format

When the gate blocks, the stderr message names the offending term, the file it appeared in, and BOTH remediation paths (add a glossary entry OR add a parenthetical definition in-context). Format:

```
================================================================
DEFINITION-ON-FIRST-USE GATE — COMMIT BLOCKED
================================================================

Undefined acronym: 'QQQ'
Found in:          neural-lace/build-doctrine/some-doc.md
Glossary checked:  ~/claude-projects/Build Doctrine/outputs/glossary.md

Remediation (pick one):
  1. Add an entry to glossary.md:
     **QQQ** — <one-line definition>.
  2. Define in-context in the same diff:
     QQQ (foo bar baz) ...

Stopwords (universally-understood, never flagged): OK, OR, JSON, URL, ...

[definition-first-use] file=neural-lace/build-doctrine/some-doc.md term=QQQ
================================================================
```

The message is the single most-important UX lever for the gate — failure should make the fix obvious.

## Alternatives considered

- **Alt 1 — LLM-based acronym extraction.** Rejected. A language model can parse "what is an acronym vs. what is an all-caps title" with higher accuracy, but the cost is non-determinism, latency at every commit, and the inability to self-test. The mechanical regex is bounded, fast (<200ms typical), and has no API dependency.

- **Alt 2 — Broader regex (e.g., `\b[A-Z][A-Za-z]{1,9}\b` to catch CamelCase product names).** Rejected. Mixed-case identifiers are typically code symbols (component names, type names) — they have their own definition-discovery story (the type system, the import path). Including them would flood the gate with false-positives. The 2-6 all-caps bound is the sweet spot.

- **Alt 3 — Per-file glossary (each `*.md` declares its own acronyms).** Rejected. Defeats the purpose of having one glossary. A reader of doc X who doesn't know acronym Q would have to look for X's per-file glossary. Single-glossary mirrors how published technical docs work.

- **Alt 4 — Blacklist (flag specific known-bad acronyms) instead of allowlist.** Rejected. The blacklist would have to be exhaustive to be useful. The current rule is "every uppercase token IS an acronym unless allowlisted" — that's the discipline the gate is meant to enforce. Inverting it would let new undefined acronyms through silently.

## Consequences

**Enables:**
- Every new acronym in a `neural-lace/build-doctrine/` doc is either in the glossary or defined in-context. The "undefined drift" failure mode is closed mechanically.
- Future ADRs that introduce acronyms get the same treatment (when the scope-prefix is widened in a future iteration).
- The glossary becomes load-bearing, not decorative. New terms get added as they enter the doctrine docs.
- Reviewers no longer have to remember to check for undefined acronyms; the gate is the check.

**Costs:**
- One extra commit-time check (~200ms typical for the regex scan + glossary lookup). Not user-visible at the latency level; visible only when it FAILS.
- Authors will hit the gate occasionally on legitimate new acronyms and have to either define-in-context or add to glossary. The remediation is fast (one line) and the gate's stderr message makes it obvious.
- The stopword allowlist will need maintenance over time as new ambiguous all-caps terms surface. Maintenance is "edit the list in the hook"; small cost.

**Depends on:**
- The glossary is at `~/claude-projects/Build Doctrine/outputs/glossary.md` OR `${REPO}/build-doctrine/outputs/glossary.md`. The hook tries the first path, falls back to the second, and degrades gracefully (warn, do not block) if neither exists.
- Authors maintain glossary entries when they introduce common-use acronyms. This is the same discipline that motivated the glossary in the first place.

**Propagates downstream:**
- `vaporware-prevention.md` enforcement map — adds a new row pointing at the new hook (Task 4 of the plan).
- `harness-architecture.md` inventory — adds a row for the new hook + new rule (Task 4 of the plan).
- `docs/backlog.md` — sub-gap G transitions from open to "Recently implemented" (Task 4 of the plan).

**Blocks:** nothing. The gate is no-op for any commit that doesn't touch in-scope `*.md` files.

## Cross-references

- `docs/plans/phase-1d-f-definition-on-first-use.md` — the implementing plan
- `adapters/claude-code/hooks/definition-on-first-use-gate.sh` — the hook (lands in Task 2)
- `adapters/claude-code/rules/definition-on-first-use.md` — the rule (lands in Task 1)
- `~/claude-projects/Build Doctrine/outputs/glossary.md` — the glossary the gate validates against
- `~/.claude/rules/harness-hygiene.md` — sibling discipline that motivates keeping doctrine docs maintainable
- HARNESS-GAP-10 sub-gap G — the backlog entry closed by this decision
