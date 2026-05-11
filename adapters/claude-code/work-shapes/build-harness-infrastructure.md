---
shape_id: build-harness-infrastructure
category: harness
required_files:
  - "adapters/claude-code/{hooks,scripts,rules,agents,templates,settings.json.template}/<artifact>"
  - "~/.claude/<corresponding-mirror-path>/<artifact>"
mechanical_checks:
  - "find adapters/claude-code/ -name '<changed-files>' -newer .git/HEAD 2>/dev/null | head -1 | grep -q ."
  - "bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test 2>&1 | grep -F 'self-test: OK'"
  - "for f in <changed-self-testable-files>; do bash \"$f\" --self-test 2>&1 | grep -F 'self-test: OK' || exit 1; done"
  - "diff -q adapters/claude-code/<path> ~/.claude/<path> >/dev/null"
  - "git log -1 --pretty=format:%s | grep -qE '^(feat|fix|refactor|docs|chore)\\(harness'"
worked_example: adapters/claude-code/hooks/local-edit-gate.sh
---

# Work Shape — Build Harness Infrastructure

## When to use

When the work creates or modifies harness infrastructure itself — files under `adapters/claude-code/` (and the live mirror at `~/.claude/`). This includes hooks, scripts, rules, agents, templates, settings.json wiring, schemas, work-shapes, and skills. The work product is the harness; there is no end-user product surface to advocate for, no UI to test in a browser, no API contract for a downstream consumer.

**Use this shape when the work matches ALL of:**

- Every file in `## Files to Modify/Create` is under `adapters/claude-code/` OR is a corresponding live-mirror path under `~/.claude/`.
- The work has no user-observable runtime behavior (it changes how the harness gates/observes/guides agent work, not what the product does).
- Verification is structural: did the file land, does the self-test pass, does the live mirror match the canonical.

**Do NOT use this shape when:**

- The work touches downstream product files (`src/`, `app/`, `docs/<product>/`, etc.) — use `build-hook` + product-specific shapes.
- The work introduces a user-facing CLI or surface that downstream maintainers will invoke directly — that's product-shaped, even if it lives under `adapters/`.
- The change introduces a third-party dependency, recurring cost, or external service binding — escalate to a full plan with ADR.

## The lighter process — what's removed

Harness infrastructure work iterates rapidly and has no end-user observation surface. Several gates and disciplines that exist for product code are explicitly relaxed:

| Discipline | Product-code default | Harness-infrastructure carve-out |
|---|---|---|
| Plan mode | `Mode: code` or `Mode: design` per `design-mode-planning.md` triggers | Always `Mode: code` — harness work doesn't need systems-designer review |
| Systems-designer review | Required for `Mode: design` plans | Replaced by self-test coverage requirement (each new mechanism ships with `--self-test`) |
| `plan-reviewer.sh` Check 4b (walking-skeleton integration-vaporware defense) | Blocks plans that lack a `## Walking Skeleton` section identifying the thinnest end-to-end slice touching every architectural layer (UI → API → worker → DB → notification) | **Advisory (warn-only)** — the check still runs and findings are surfaced on stderr, but the gate does not block when every file in `## Files to Modify/Create` resolves to a path under `adapters/claude-code/`. Rationale: harness mechanisms have no user-observable runtime; "the user clicks X and sees Y" doesn't apply when the "user" is a hook firing at an event boundary and the observable behavior is `--self-test` passing. |
| Spec-freeze gate | Edits to declared files require `frozen: true` | Not required — harness work iterates rapidly and adds files mid-build as new mechanisms are discovered. The `## In-flight scope updates` section absorbs additions without thaw cycles. |
| `end-user-advocate` plan-time / runtime acceptance | Required unless `acceptance-exempt: true` with reason | Always exempt — declare `acceptance-exempt: true` + `acceptance-exempt-reason: harness-internal work; self-tests are the acceptance artifact`. |
| Runtime user-observable acceptance artifact | JSON PASS artifact at `.claude/state/acceptance/<slug>/` from running app | **Self-test PASS is the acceptance artifact.** A hook with `bash <hook>.sh --self-test 2>&1 \| grep -F 'self-test: OK'` is the harness's native verification idiom. |
| `prd-ref:` field | Resolves to `docs/prd.md` with seven substantive sections | Use the harness-development carve-out: `prd-ref: n/a — harness-development` (exact string per Decision 015c). |
| Plan file required at all | Required for any non-trivial multi-step work | Plan file optional for narrow single-purpose changes (one hook, one rule edit, one self-test extension). For multi-task work (≥ 2 tasks in different files), still write a plan — but the plan is lightweight and references this shape. |

## What IS still enforced

These layers remain mechanical and non-negotiable. Harness work doesn't get to bypass safety perimeters:

- **`pre-commit-tdd-gate.sh`** — credential / secret scanning on every staged file. Identical behavior; harness files are scanned the same as product files.
- **`harness-hygiene-scan.sh`** — no project-specific identifiers, no real emails, no employer names, no absolute paths with usernames. Layer 2 heuristic detection (project-internal path shapes, repeated capitalized-term clusters) applies. This is the load-bearing perimeter that keeps the harness a generic kit; it does not relax for harness-internal work.
- **`docs-freshness-gate.sh`** — when adding a hook, the architecture doc (`docs/harness-architecture.md`) must be updated in the same commit. When adding a rule, the rules-table reference. The discipline of keeping inventory docs current is identical for product work.
- **`pre-push-scan.sh`** — credential pattern scanning at push time. Identical behavior.
- **All existing `--self-test` blocks must still pass.** This is the harness's native verification rubric. A change to one hook that breaks an unrelated hook's self-test indicates a regression and blocks the commit.
- **`harness-maintenance.md` two-layer-config discipline** — every change to `adapters/claude-code/` is mirrored to `~/.claude/` (or vice-versa), and `diff -q` confirms byte-identical content. The install path is `cp`-based on Windows, symlink-based on Unix, but the post-condition (byte-identical) is the same.
- **`git.md` commit-message convention** — `feat(harness): ...`, `fix(harness): ...`, `docs(harness): ...`, `refactor(harness): ...`, `chore(harness): ...`. The `(harness)` scope is the audit-trail breadcrumb that makes harness-infrastructure work greppable.
- **`scope-enforcement-gate.sh`** — when a plan is open, commits respect its `## Files to Modify/Create` (or `## In-flight scope updates`) declaration. The discipline holds even when the plan is light.

## Structure

A compliant harness-infrastructure change produces:

1. **The canonical file(s)** under `adapters/claude-code/{hooks,scripts,rules,agents,templates,work-shapes,schemas,skills,settings.json.template}/`. Each artifact follows its sub-shape conventions:
   - Hooks: see `build-hook.md` (header, `set -euo pipefail`, `--self-test`, exit codes, stderr-with-remediation).
   - Rules: see `build-rule.md` (Classification line, Why-this-rule-exists, Cross-references, Scope).
   - Agents: see `build-agent.md`.
   - ADRs / decisions: see `author-ADR.md`.
   - Self-tests: see `write-self-test.md`.
2. **Live mirror** at the corresponding `~/.claude/<path>`, byte-identical to canonical. Verified by `diff -q`.
3. **`docs/harness-architecture.md` row** when adding a new hook, agent, rule, or skill — the inventory must reflect the addition.
4. **Commit message scoped `(harness)`** — `feat(harness): ...`, `docs(harness): ...`, etc.

If the change adds a new mechanism (hook, agent, gate), it MUST also:

5. **Ship with `--self-test`** that exercises pass/fail scenarios with synthetic inputs.
6. **Be wired in `settings.json.template`** under the appropriate event matcher if it's a hook. The corresponding `~/.claude/settings.json` is updated in the same operation.

If the change introduces a Tier 2+ decision (architectural pattern, new convention, scope choice), it MUST also produce:

7. **An ADR** at `docs/decisions/NNN-<slug>.md` plus an index row in `docs/DECISIONS.md`, landed in the same commit (per `decisions-index-gate.sh` atomicity).

## Common pitfalls

- **Forgetting the live mirror.** Two-layer config: `adapters/claude-code/` is the committed source-of-truth; `~/.claude/` is what the running session reads. Editing only one leaves the running session reading the old version. Always sync; always `diff -q` to verify.
- **Skipping `--self-test`.** A hook without a self-test cannot be regression-tested when adjacent code changes. The self-test IS the acceptance artifact under this shape; without it, there is no verification rubric.
- **Treating Check 4b advisory as "ignore it."** The check still runs and surfaces findings on stderr. Read the findings — they may name an integration gap that would matter for product code. Advisory means "this won't block the commit," not "this won't tell you anything useful." If the finding is genuinely irrelevant (no user surface exists), proceed; if it points at a real ambiguity in how the mechanism integrates, fix it before commit. The simplest path: declare `Walking Skeleton: n/a — harness-internal work; self-test is the end-to-end slice` on a single line in the plan, which both satisfies the check substantively and documents the carve-out for future readers.
- **Using `acceptance-exempt: true` without the harness-internal reason.** The reason field is parsed by `product-acceptance-gate.sh`. A reason like `n/a` (≤ 20 chars) is BLOCKED. Use the canonical form: `acceptance-exempt-reason: harness-internal work; self-tests are the acceptance artifact`.
- **Skipping the architecture-doc update.** `docs-freshness-gate.sh` will block the commit. Add the new hook/agent/rule to the appropriate table in `docs/harness-architecture.md` in the same diff.
- **Adding a new mechanism without considering the enforcement-map row.** `rules/vaporware-prevention.md` maintains an enforcement-map table. New mechanisms should add a row so future readers can see "this gate exists and these are its semantics" without code-reading.
- **Conflating harness-infrastructure work with downstream-project work.** If a single change touches both `adapters/claude-code/` AND product files (e.g., `src/app/foo/page.tsx`), it does NOT qualify for this shape — split into two commits or two plans. The shape's carve-outs only apply when every modified file is under the harness path.
- **Adding a third-party dependency without an ADR.** Recurring-cost decisions, new external service bindings, and new package dependencies are Tier 2+ — they need an ADR even when they live in harness infrastructure. Don't use the lighter process to dodge the ADR requirement.
- **Hand-rolling a self-test pattern that doesn't print `self-test: OK`.** The mechanical check `grep -F 'self-test: OK'` is the convention. Self-tests that exit 0 silently or print a different success token break the work-shape's verification rubric.

## Worked example walk-through

`adapters/claude-code/hooks/local-edit-gate.sh` (committed 2026-05-09 as part of context-aware permission gates / ADR 029) exemplifies the shape:

- **Scope:** every modified file in the commit lives under `adapters/claude-code/` or `~/.claude/`. No product files touched.
- **Mode: code** — no systems-designer review invoked. The hook's behavior is mechanical and self-testable.
- **Plan was minimal:** a thin task list referencing this shape rather than the full 10-section Systems Engineering Analysis.
- **`--self-test` is the acceptance artifact** — the hook ships with a self-test block that exercises both the default-block path (no marker) and the allow path (fresh authorized marker). Running `bash hooks/local-edit-gate.sh --self-test 2>&1 | grep -F 'self-test: OK'` is the entire acceptance check.
- **Live mirror sync** — committed to `adapters/claude-code/hooks/local-edit-gate.sh`; copied to `~/.claude/hooks/local-edit-gate.sh`; `diff -q` confirms byte-identical.
- **Wired in `settings.json.template`** under `hooks.PreToolUse` matching `Edit|Write|MultiEdit`. The live `~/.claude/settings.json` carries the same wiring.
- **ADR produced** — ADR 029 at `docs/decisions/029-local-edit-authorization-mechanism.md` plus index row in `docs/DECISIONS.md`, landed atomically with the mechanism (per `decisions-index-gate.sh`).
- **Architecture doc updated** — `docs/harness-architecture.md` was extended with a row for `local-edit-gate.sh`.
- **`harness-hygiene-scan.sh` passed** — no project-specific identifiers in the hook body, in the rule, or in the ADR.
- **Commit message scoped `(harness)`** — `feat(harness): context-aware permission gates — session-wrap worktree fall-back + local-edit authorization`.

The full work shipped in three commits over a single session without invoking systems-designer, without authoring a 10-section design plan, and without writing a runtime acceptance scenario. The self-test passing + the byte-identical live mirror + the harness-hygiene scan + the ADR atomicity gate together provided sufficient verification.

## Cross-references

- `adapters/claude-code/rules/harness-maintenance.md` — the two-layer-config discipline and live-mirror sync workflow.
- `adapters/claude-code/rules/harness-hygiene.md` — what never ships in harness code (identifiers, credentials, project-specific paths).
- `adapters/claude-code/rules/planning.md` "Work-shape: build-harness-infrastructure" — when the lighter process applies and what it removes vs. preserves.
- `adapters/claude-code/work-shapes/build-hook.md` — composed sub-shape for hooks.
- `adapters/claude-code/work-shapes/build-rule.md` — composed sub-shape for rules.
- `adapters/claude-code/work-shapes/build-agent.md` — composed sub-shape for agents.
- `adapters/claude-code/work-shapes/author-ADR.md` — composed sub-shape for Tier 2+ decisions.
- `adapters/claude-code/work-shapes/write-self-test.md` — composed sub-shape for `--self-test` blocks.
- `adapters/claude-code/rules/vaporware-prevention.md` — enforcement-map showing what gates remain active and what relaxes.

## Notes on advisory-mode Check 4b

`plan-reviewer.sh` Check 4b (walking-skeleton integration-vaporware defense) is advisory when EVERY entry in the plan's `## Files to Modify/Create` section resolves to a path under `adapters/claude-code/`. Specifically:

- The check still parses the plan and looks for the `## Walking Skeleton` section.
- Findings are still printed to stderr — so the maintainer sees what the check would have surfaced.
- The findings are NOT added to `FINDING_COUNT` (the gate's blocking aggregate), so the plan can move to ACTIVE without authoring a walking-skeleton section.
- A single product-file path in `## Files to Modify/Create` flips the plan back to blocking-mode Check 4b. Mixed-scope plans (product + harness) are treated as product-scope for this check.
- Path resolution is literal-prefix: a bullet whose backtick-delimited path starts with `adapters/claude-code/` (or the live-mirror prefix `~/.claude/`) qualifies as harness-scope. Other paths (`src/`, `app/`, `docs/`, bare-relative paths without the prefix) flip the plan back to product-scope.

Rationale: harness mechanisms have no user-observable runtime. "The user clicks the Save button and sees the form persist" doesn't apply when the "user" is a `PreToolUse` hook firing at an event boundary and the "observable behavior" is `--self-test` passing. The contract Check 4b enforces (thinnest end-to-end slice through every architectural layer) is incoherent for harness infrastructure because the layer-count is one (the hook itself) and the slice IS the self-test. Keeping the check advisory preserves the audit trail without imposing a Goodhart-shaped friction on every harness commit.
