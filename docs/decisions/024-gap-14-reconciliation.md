# Decision 024 — GAP-14 template-vs-live reconciliation outcomes

**Date:** 2026-05-04
**Status:** Implemented
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-e-3-gap-14-reconciliation.md` (Status: ACTIVE → COMPLETED on this commit)
**Related backlog item:** HARNESS-GAP-14 (closed by this plan)
**Related audit:** `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md`

## Context

HARNESS-GAP-14 tracked the reconciliation half of the discovery `2026-05-04-template-vs-live-divergence-across-other-hooks`. The detector half — `settings-divergence-detector.sh` — shipped earlier in the session. Five hooks were known to have pre-existing divergence between `adapters/claude-code/settings.json.template` (committed source-of-truth for `install.sh`) and `~/.claude/settings.json` (gitignored live config). Some were present only in template; some only in live; one had divergent command-string forms in opposite directions.

The user explicitly pushed back on framing this as "user picks canonical side per hook" and asked for orchestrator-driven research. Per-hook research, evidence-cited proposals, and auto-apply for REVERSIBLE outcomes are the discipline.

## Decision

Six per-hook verdicts, all REVERSIBLE, all auto-applied per the discovery-protocol decide-and-apply rule:

### 024a — `outcome-evidence-gate.sh` → live → template

Originating commit `e3d5f0a` (2026-04-19). The Gen 5 hook shipped with hook file + rule + architecture-doc inventory entry but the template was never updated. Live form is canonical; added an `Edit|Write` PreToolUse entry to the template at the matching position.

### 024b — `systems-design-gate.sh` → live → template

Originating commit `483f5f6` (2026-04-19). Same drift pattern as 024a. Added `Edit|Write` PreToolUse entry to template adjacent to outcome-evidence-gate.

### 024c — `no-test-skip-gate.sh` → live → template

Originating commit `5c8e3e4` (2026-04-20). Same drift pattern. Added `Bash` PreToolUse entry to template.

### 024d — `check-harness-sync.sh` (composition) → live → template

Originating commit `fa50661` (Initial release v1.0). The hook shipped at v1.0 as a SessionStart hook; was later composed into the pre-commit Bash hook flow with hard-fail semantics replacing the older `|| true` form. Live's command-string composition is canonical: `check-harness-sync.sh` runs first (cheap; exits early if drift exists), then `pre-commit-gate.sh` (expensive); both hard-fail. Updated the template's pre-commit Bash command-string accordingly. Status message also updated to match.

### 024e — Public-repo blocker → template → live

This was the only divergence going the OPPOSITE direction. Template form is more elaborate — it adds a `read-local-config.sh public-blocked` lookup so the block message can identify whether the current account/directory is policy-blocked vs. just guard-blocked. Live form was the older simple form. Upgraded live's command-string to match template's elaborate form. Both forms produce the same block-with-exit-1 outcome on the trigger pattern; the elaborate form just adds an additional informational line about policy-block status.

### 024f — Force-push / `--no-verify` Bash blocker → live → template

The plan's "public-repo-blocker variants" reference resolved to include the adjacent force-push / `--no-verify` blocker which sits next to the public-repo blocker in live. Live form is canonical; added a `Bash` PreToolUse entry to template adjacent to the public-repo blocker. Enforces existing rule-level discipline (`rules/git.md` "Safe push methods", `rules/security.md` destructive-ops clause) on every install.

### 024g — `tool-call-budget.sh` matcher tightening (incidental cleanup)

Template's `.*` matcher was loosened from the architecture-doc's documented form (`Edit|Write|Bash`) — likely a stale pre-Gen-5 artifact. Tightened the template matcher to `Edit|Write|Bash` to match live and the documented enforcement scope (avoids firing on Read-only tools).

## Alternatives Considered

- **Per-hook user-judgment review (the originally-tabled option).** Rejected per user directive: the user explicitly asked for orchestrator-driven research with evidence citations, not "user picks canonical side cold." All six verdicts above are evidenced; the user's role is to spot-check and course-correct, not to decide.
- **Resolve all divergences at once including SessionStart and UserPromptSubmit.** Rejected as scope-creep. Six additional divergences (per-project-paths-in-global-hook drift in compact-recovery, missing automation-mode initializer in live, legacy `claude-config` path in template, automation-mode-aware title bar) are real but out of GAP-14's named scope. Surfaced in the audit doc as follow-up; tracked as a new backlog item.
- **Add a `harness-divergence-allowlist.txt` for intentional divergences.** Rejected for now — none of the six in-scope reconciliations are intentional divergences. If future work surfaces a hook that legitimately should differ between template and live (e.g., a maintainer-specific debugging hook), the allowlist mechanism can be added then.

## Consequences

**Enables:**
- Fresh `install.sh` runs from a clean machine now wire all five missing hooks. No more "harness's claimed enforcement may not match its actual enforcement on a fresh install."
- `settings-divergence-detector.sh` PreToolUse counts now equal between template and live (template=23, live=23).
- The plan's named four hooks plus public-repo + force-push variants are reconciled.

**Costs:**
- Template now declares hooks that did not exist at v1.0 — fresh installs against the v1.0 hook directory layout would error. This is moot in practice because the hook files themselves have shipped in the repo for months and are present in any current `install.sh` run.
- One genuine divergence remains intentional-by-omission: the `~/.claude/settings.json` is gitignored, so the public-repo command-string upgrade applied in this session lives only on this machine. Future `install.sh` runs (which copy template → live) will write the elaborate form by default; existing installs where the live file pre-dates this session will need the upgrade applied manually or via re-running install. Documented in the rule cross-references.

**Blocks (out of scope; tracked as follow-up):**
- SessionStart compact-recovery per-project-paths drift in live.
- SessionStart automation-mode initializer missing from live.
- SessionStart legacy `claude-config` path in template (predates rename to `neural-lace`).
- UserPromptSubmit title-bar automation-mode awareness divergence.

A new backlog entry — `HARNESS-GAP-14-followups` or absorbed into the next harness-cleanup phase — should track these.
