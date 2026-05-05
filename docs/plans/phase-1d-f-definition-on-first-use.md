# Plan: Phase 1d-F — Definition-on-first-use enforcement

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-GAP-10 sub-gap G
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product-user surface to verify at runtime. Verification is via per-hook `--self-test` invocations + manual round-trip exercising the acronym scan against a synthetic markdown file with mixed defined / undefined first-use acronyms.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Context

HARNESS-GAP-10 sub-gap G: Build Doctrine + NL docs use ~50+ acronyms heavily. The user requested a glossary, which now lives at `~/claude-projects/Build Doctrine/outputs/glossary.md` (322 lines). To prevent recurring drift where new docs introduce undefined acronyms, definition-on-first-use should be enforced mechanically.

Per the backlog: "Proposed mechanism: pre-commit hook that scans every `*.md` under `neural-lace/build-doctrine/` for first-use acronyms (regex-detected), requiring either a definition-in-context or a cross-reference to `glossary.md`."

This phase ships that mechanism.

## Goal

A new pre-commit hook `definition-on-first-use-gate.sh` that:
1. On every commit modifying `*.md` files in scope (initially `neural-lace/build-doctrine/**/*.md`; configurable), scans the staged diff.
2. For each newly-added acronym (regex `\b[A-Z]{2,6}\b` minus a stopword allowlist for common English words), check if it is defined in the staged diff itself OR appears in `glossary.md`.
3. Block the commit if any new acronym is undefined and not in the glossary; provide a clear remediation message naming the offending term.

Plus enabling work:
- Decision 023 (definition-on-first-use semantics — locks the acronym regex, the stopword list, the scope-prefix scope, the failure message format).
- New rule `adapters/claude-code/rules/definition-on-first-use.md`.
- Extension of `vaporware-prevention.md` enforcement map: 1 new row.
- Extension of `harness-architecture.md` inventory: 1 new hook + 1 new rule.

## Scope

**IN:**
- `adapters/claude-code/hooks/definition-on-first-use-gate.sh` — NEW pre-commit hook with `--self-test`.
- `~/.claude/hooks/definition-on-first-use-gate.sh` — sync target (gitignored mirror).
- `adapters/claude-code/settings.json.template` — EDIT (wire into pre-commit chain — PreToolUse Bash on `git commit`).
- `~/.claude/settings.json` — EDIT (mirror).
- `adapters/claude-code/rules/definition-on-first-use.md` — NEW rule.
- `~/.claude/rules/definition-on-first-use.md` — sync target.
- `adapters/claude-code/rules/vaporware-prevention.md` — EDIT (add 1 enforcement-map row).
- `docs/decisions/023-definition-on-first-use-enforcement.md` — NEW.
- `docs/DECISIONS.md` — EDIT.
- `docs/harness-architecture.md` — EDIT.
- `docs/backlog.md` — EDIT (mark sub-gap G as IMPLEMENTED in Recently Implemented section).

**OUT:**
- Glossary maintenance (the user maintains glossary.md manually for now).
- Acronym definition QA (the gate enforces presence, not quality).
- Per-project glossary (only NL build-doctrine scope for v1).
- LLM-assisted acronym extraction (mechanical regex only).

## Tasks

- [ ] **1. Decision 023 + rule documentation.** Land Decision 023 (acronym regex `\b[A-Z]{2,6}\b`; stopword allowlist for common English uppercase words; scope-prefix is initially `neural-lace/build-doctrine/`; failure message format names offending term + suggests glossary entry or in-context definition). Create `adapters/claude-code/rules/definition-on-first-use.md` documenting when the gate fires and how authors should respond. Update `docs/DECISIONS.md`. Single commit.

- [ ] **2. Hook implementation `definition-on-first-use-gate.sh`.** NEW pre-commit hook (PreToolUse Bash on `git commit`). On commit modifying `*.md` files in scope, parse the staged diff via `git diff --cached`, extract new acronyms, look up each in glossary.md OR confirm defined in the same diff. Block if any new acronym is undefined. `--self-test` with 5+ scenarios (PASS-no-md-changes, PASS-defined-in-glossary, PASS-defined-in-diff, FAIL-undefined-acronym, PASS-stopword-not-flagged). Test before commit. Sync to live. Single commit.

- [ ] **3. Wire hook + glossary path resolution.** EDIT `adapters/claude-code/settings.json.template` to add the hook to PreToolUse Bash chain, position after `harness-hygiene-scan.sh`. The hook reads glossary path from a configured location (e.g., `~/.claude/local/personal.config.json` for the user's glossary path; falls back to `${REPO}/build-doctrine/outputs/glossary.md` if found). Mirror to live. Single commit.

- [ ] **4. Inventory + enforcement-map + backlog cleanup.** Add inventory row to `docs/harness-architecture.md` for the new hook + new rule. Add row to `vaporware-prevention.md` enforcement map. Mark sub-gap G as IMPLEMENTED in `docs/backlog.md` "Recently implemented" section with commit SHA. Single commit.

## Files to Modify/Create

- `adapters/claude-code/hooks/definition-on-first-use-gate.sh` — NEW.
- `~/.claude/hooks/definition-on-first-use-gate.sh` — sync.
- `adapters/claude-code/rules/definition-on-first-use.md` — NEW.
- `~/.claude/rules/definition-on-first-use.md` — sync.
- `adapters/claude-code/settings.json.template` — EDIT.
- `~/.claude/settings.json` — EDIT (gitignored mirror).
- `adapters/claude-code/rules/vaporware-prevention.md` — EDIT.
- `docs/decisions/023-definition-on-first-use-enforcement.md` — NEW.
- `docs/DECISIONS.md` — EDIT.
- `docs/harness-architecture.md` — EDIT.
- `docs/backlog.md` — EDIT.

## In-flight scope updates

(none yet)

## Assumptions

- Acronym detection via `\b[A-Z]{2,6}\b` is sufficient. Mixed-case acronyms (e.g., camelCase identifiers, code symbols) are NOT flagged. The 2-6 character bound covers common acronyms (PRD, ADR, LLM, ITPM) without flooding noise.
- The stopword allowlist for common English uppercase words includes: `OK`, `OR`, `AND`, `IF`, `IS`, `OF`, `BY`, `IN`, `ON`, `AT`, `TO`, `THE`, `A`, `WHO`, `WHAT`, `WHERE`, `WHEN`, `WHY`, `HOW`, `JSON`, `YAML`, `TOML`, `URL`, `URI`, `HTTP`, `HTTPS`, `API`, `CLI`, `GUI`, `UI`, `UX`, `CSS`, `HTML`, `JS`, `TS`, `SQL`, `MD`, `PDF`, `PNG`, `JPG`, `GIF`. The list will grow over time; first iteration is best-effort.
- "Defined in glossary" means the term appears as a row entry (e.g., `## TERM` or `| TERM |`) in `glossary.md`.
- "Defined in diff" means the term is followed within ~30 chars by an explanatory phrase (e.g., `LLM (large language model)`) — the regex looks for `<TERM>\s*\(.+?\)` or `<TERM>\s*[—-]\s*` patterns.
- Initial scope-prefix is `neural-lace/build-doctrine/`. The hook can be extended to other paths later via configuration.
- The hook degrades gracefully if `glossary.md` is missing — outputs a warning but does not block.
- Plan-reviewer's existing checks won't conflict with this new acronym-detection regex (they operate on different content types).

## Edge Cases

- **Modified `*.md` outside `neural-lace/build-doctrine/`.** Hook is a no-op for those — only scoped-prefix matches trigger acronym detection.
- **Acronym appears in the diff for the first time AND glossary.md is also modified to add it.** The hook should accept this — an acronym defined in the same diff in glossary is a legitimate first-use+definition pair.
- **Acronym is a stopword (e.g., `URL`).** Not flagged.
- **Acronym is in-context defined within the SAME diff via parenthetical: `LLM (large language model)`.** Accepted as "defined in diff".
- **Acronym appears in `glossary.md` but the format doesn't match the parser's expectation.** False negative (gate blocks). Workaround: author can use `## ACRONYM` heading or table row format that the parser recognizes. Future iteration may relax the parser.
- **Acronym appears multiple times in the same diff.** Only first occurrence is checked; subsequent uses are silent.
- **Commit modifies a previously-committed `*.md` to ADD a new acronym.** Hook detects the new acronym in the diff and applies the rules.
- **Committer wants to bypass the gate (legitimate edge case e.g., a typo fix introducing a real acronym that needs glossary updating in a follow-up).** Use `git commit --no-verify` per the standard escape hatch.

## Acceptance Scenarios

(none — `acceptance-exempt: true`. Verification per task: hook self-test PASS + manual round-trip with synthetic markdown.)

## Out-of-scope scenarios

- Glossary maintenance (acronym definition QA, link-checking, completeness audit).
- Cross-project glossary sharing.
- LLM-assisted glossary entry generation.

## Testing Strategy

Each task task-verified. Specific testing per task:

1. **Task 1 (Decision + rule):** Decision 023 file exists with required sections; rule file exists with substance.
2. **Task 2 (Hook):** `bash adapters/claude-code/hooks/definition-on-first-use-gate.sh --self-test` PASS. Manual round-trip: create a synthetic markdown file with one defined-in-glossary acronym and one undefined acronym, stage it, run the hook. The hook should block on the undefined one.
3. **Task 3 (Wiring):** confirm the hook appears in both template and live `settings.json` PreToolUse Bash chain. Run `cat settings.json | jq -e .` to confirm JSON validity.
4. **Task 4 (Inventory + cleanup):** harness-architecture.md has the new row; vaporware-prevention.md enforcement map has the new row; backlog.md "Recently implemented" includes the sub-gap G entry.

## Walking Skeleton

The minimum viable shape: a hook that does ONE thing well — detect ONE undefined acronym in a synthetic test markdown file under the scoped prefix. Once that round-trip works, generalize to multi-acronym cases.

## Decisions Log

(populated during implementation; Decision 023 is landed by Task 1)

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept, 0 matches stranded.
- S2 (Existing-Code-Claim Verification): swept, 4 claims (glossary.md path; build-doctrine/ exists at that path; pre-commit chain in settings.json; harness-architecture.md inventory format) — all 4 verified.
- S3 (Cross-Section Consistency): swept, 0 contradictions.
- S4 (Numeric-Parameter Sweep): swept for [acronym regex 2-6 chars, scope path neural-lace/build-doctrine/] — values consistent.
- S5 (Scope-vs-Analysis Check): swept, 0 contradictions; Scope OUT items (glossary maintenance, cross-project glossary, LLM-assisted) not contradicted.

## Definition of Done

- [ ] All 4 tasks task-verified PASS.
- [ ] Hook self-test PASS with 5+ scenarios.
- [ ] Manual round-trip exercised against synthetic markdown.
- [ ] Decision 023 landed and indexed.
- [ ] Backlog reflects HARNESS-GAP-10 sub-gap G as IMPLEMENTED.
- [ ] Plan archived (Status: COMPLETED → auto-archive).
