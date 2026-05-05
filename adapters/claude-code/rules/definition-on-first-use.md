# Definition-on-first-use — Acronyms in Doctrine Docs Must Be Defined Before They're Used

**Classification:** Mechanism (hook-enforced). The discipline of either adding a glossary entry OR adding a parenthetical definition is Pattern-level (the author self-applies). The mechanical block at commit time is enforced by `adapters/claude-code/hooks/definition-on-first-use-gate.sh` (PreToolUse Bash on `git commit`). When the gate fires and finds an undefined acronym, the commit is blocked with a clear remediation message naming both paths.

**Ships with:** Decision 023 (`docs/decisions/023-definition-on-first-use-enforcement.md`) — the five locked sub-decisions (regex, stopword allowlist, scope-prefix, "defined" semantics, failure message format).

## Why this rule exists

Build Doctrine and Neural Lace docs use ~50+ acronyms heavily (PRD, ADR, DAG, LLM, ITPM, RPM, TPM, NEPQ, RLS, TDD, ...). A reader new to the doctrine encounters the acronyms and has no shared substrate to look them up. The glossary at `~/claude-projects/Build Doctrine/outputs/glossary.md` (322 lines) closes that gap as a single-source-of-truth.

But the glossary is necessary, not sufficient. Without enforcement, future docs introduce undefined acronyms again — the same drift the glossary was meant to close. The gate is the enforcement: every commit modifying in-scope `*.md` files is checked, and every new acronym must be either in the glossary OR defined in-context within the same diff.

The user-trust rationale: a reader of any doctrine doc can trust that every uppercase 2-6 char token IS a defined acronym, not a typo, not a random capitalization, not an undocumented internal codename.

## When the gate fires

The gate fires on `git commit` and inspects the staged diff. It activates when **at least one staged file matches the scope-prefix `neural-lace/build-doctrine/**/*.md`** (per Decision 023c). For commits that touch zero in-scope files, the gate is a no-op and exits silently.

For each in-scope file, the gate:

1. Reads the staged diff via `git diff --cached -- <path>`.
2. Extracts the `+` (added) lines.
3. Scans each added line for tokens matching `\b[A-Z]{2,6}\b` (Decision 023a).
4. Filters out the stopword allowlist (Decision 023b).
5. For each remaining acronym, checks both definition paths (Decision 023d):
   - **In glossary**: searches `~/claude-projects/Build Doctrine/outputs/glossary.md` (with fallback to `${REPO}/build-doctrine/outputs/glossary.md`) for `**TERM**`, `## TERM`, `### TERM`, or `| TERM |`.
   - **In diff**: searches the same staged diff for `<TERM>\s*\(.{2,40}\)` where the parenthetical contains at least 2 words.
6. If both checks fail for any acronym, BLOCKS the commit with the failure message format from Decision 023e.

If the glossary file is missing entirely, the gate emits a warning and ALLOWS the commit (graceful degradation — the author shouldn't be blocked because the glossary path is misconfigured).

## What authors should do

When the gate blocks on an undefined acronym, the author has two remediation paths, both fast.

**Path A — Add to glossary.** Open `~/claude-projects/Build Doctrine/outputs/glossary.md`, find the appropriate section (or add to the alphabetical index), and add:

```
**XYZ** — <one-line definition>. [Optional: cross-reference to where it's used.]
```

Re-stage the glossary, re-stage the originating doc, commit. The gate will now PASS.

**Path B — Define in-context.** In the originating doc itself, on the line introducing the acronym, add a parenthetical definition:

```markdown
The XYZ (cross-system Y zone) ensures that ...
```

The parenthetical must be within ~30 chars of the term and must contain at least 2 words. Single-word parentheticals (e.g., `XYZ (alias)`) are NOT recognized as definitions — they read as aliases, not definitions.

**When to use which path.** Path A is preferred for terms that will be used in more than one doctrine doc. Path B is preferred for one-off terms that appear once and don't need glossary real estate.

## Acronym detection regex

The regex is `\b[A-Z]{2,6}\b`. Concretely:

| Token | Match? | Reason |
|---|---|---|
| `LLM` | Yes | 3 uppercase chars, word-boundary on both sides |
| `PRD` | Yes | 3 uppercase chars |
| `HARNESS` | Yes | 7 chars — wait, no: 7 > 6, NOT matched |
| `OK` | Matched but skipped | In stopword allowlist |
| `URL` | Matched but skipped | In stopword allowlist |
| `JsonDocument` | No | Mixed case |
| `XML` | Matched but skipped | In stopword allowlist (file format) |
| `XYZ` | Yes (and flagged if undefined) | 3 uppercase chars, not a stopword |
| `K` | No | 1 char, below the 2-char floor |
| `OKKK` | Yes | 4 uppercase chars; not in stopword list |

The 2-6 character bound is intentional: 2 covers common short acronyms (UI, OS, CI), 6 covers common longer acronyms (HTTPS, COBRA, NASCAR). Words longer than 6 characters in all-caps are typically prose emphasis (`PERFECT`, `IMPORTANT`), not acronyms. Words shorter than 2 are single letters and not acronyms.

## Stopword allowlist

The allowlist (Decision 023b) excludes universally-understood tokens that match the regex but should never be flagged:

```
OK OR AND IF IS OF BY IN ON AT TO THE A
WHO WHAT WHERE WHEN WHY HOW
JSON YAML TOML MD PDF PNG JPG GIF SVG XML CSV TSV
URL URI HTTP HTTPS FTP SSH TLS SSL DNS
API CLI GUI UI UX CSS HTML JS TS SQL
ID IDS IP CPU GPU RAM ROM USB DVD CD
PR PRS CI CD QA RC OS
```

The list is generous on the side of false-negatives. If a term is mistakenly being flagged, the recovery is to add it to the stopword allowlist in the hook (one-line edit, single commit). The stopword list is intentionally project-agnostic — project-specific acronyms (NL, PT, etc.) are NOT stopwords; they live in the glossary.

## Examples

### PASS examples

**PASS — defined in glossary:**
```markdown
The PRD captures what the user wants and why.
```
(`PRD` is in the glossary as `**PRD** — Product Requirements Document.`)

**PASS — defined in-diff via parenthetical:**
```markdown
The XYZ (cross-system Y zone) component handles data routing.
```
(The 3-word parenthetical within ~30 chars of `XYZ` satisfies Path B.)

**PASS — stopword:**
```markdown
The URL points to the canonical resource.
```
(`URL` is in the stopword allowlist; never flagged.)

**PASS — out of scope:**
```markdown
[a commit that modifies docs/decisions/023-foo.md, not under neural-lace/build-doctrine/]
```
(The gate is a no-op for files outside the scope-prefix.)

### FAIL examples

**FAIL — undefined and not in glossary:**
```markdown
The QQQ subsystem manages caching.
```
(`QQQ` is not in the glossary, not in the stopword list, no parenthetical definition. Block.)

**FAIL — single-word parenthetical:**
```markdown
The XYZ (alias) component routes traffic.
```
(`XYZ (alias)` has only 1 word in the parenthetical. The gate requires 2+. Block.)

**FAIL — parenthetical too far away:**
```markdown
The XYZ component routes traffic. It's a long-running process. (cross-system Y zone)
```
(The parenthetical is too far from the first occurrence — beyond ~30 chars. Block.)

## Cross-references

- **Decision record:** `docs/decisions/023-definition-on-first-use-enforcement.md` — the five locked sub-decisions backing this rule.
- **Hook:** `adapters/claude-code/hooks/definition-on-first-use-gate.sh` — the PreToolUse Bash mechanism (lands in Phase 1d-F Task 2).
- **Glossary:** `~/claude-projects/Build Doctrine/outputs/glossary.md` — the canonical definition source.
- **Sibling rule (proactive learnings):** `~/.claude/rules/diagnosis.md` "After Every Failure: Encode the Fix" — the broader discipline this rule operationalizes for the specific failure class of undefined acronyms.
- **Sibling rule (durable capture):** `~/.claude/rules/harness-hygiene.md` — the rule that motivates keeping doctrine docs maintainable across maintainers.
- **Sibling rule (build-doctrine architecture):** `~/.claude/rules/findings-ledger.md` — sibling Mechanism + Pattern split (one of the templates this rule's structure mirrors).

## Enforcement

| Layer | What it enforces | File | Status |
|---|---|---|---|
| Rule (this doc) | When the gate fires; what authors should do; the regex + stopword allowlist | `adapters/claude-code/rules/definition-on-first-use.md` | landing in Phase 1d-F Task 1 |
| Hook | Mechanical block on commits with undefined acronyms in scope-prefix `*.md` | `adapters/claude-code/hooks/definition-on-first-use-gate.sh` | landing in Phase 1d-F Task 2 |
| Decision record | The five sub-decisions backing this rule | `docs/decisions/023-definition-on-first-use-enforcement.md` | landed in Phase 1d-F Task 1 |
| Wiring | Hook is registered in PreToolUse Bash chain | `adapters/claude-code/settings.json.template` | landing in Phase 1d-F Task 3 |

The rule is documentation (Pattern-level discipline). The mechanism (hook + wiring) is hook-enforced. Together they close the loop: cannot commit a doctrine doc with an undefined acronym (gate); the discipline of defining acronyms before use is the author self-applying.

## Scope

This rule applies to commits that modify `*.md` files under `neural-lace/build-doctrine/` (Decision 023c). The scope is hard-coded in v1; it can be widened to `docs/decisions/` or `docs/plans/` in a future iteration via the same hook with a configurable scope-prefix list.

Projects without a `neural-lace/build-doctrine/` directory see the gate as a no-op (no in-scope files staged means nothing to validate). Adoption is implicit — any project whose Claude Code installation has the hook wired in `settings.json` AND has a `neural-lace/build-doctrine/` tree gets the gate automatically.
