# Failure Mode Catalog

> **Purpose.** Canonical, sanitized catalog of known harness failure classes. Every new failure that surfaces during a session should either extend an existing entry (if it is the same class) or be added as a new entry (if it is a new class). Hooks, agents, and skills consult this file when evaluating uncertain claims and known-bad patterns. Every failure that is not encoded here is a failure that will repeat.

> **Scope.** Failure CLASSES, not individual incidents. Each entry generalizes from one or more concrete observations. Sanitized — no codenames, no personal identifiers, no real incident dates tied to a specific product.

> **Catalog plan.** This file is the artifact produced by the `failure-mode-catalog` plan (see `docs/plans/archive/failure-mode-catalog.md`). The companion `capture-codify-pr-template` plan wires this catalog into PR-time mechanism analysis — every PR's mechanism field references entries here by `FM-NNN` ID under answer form (a), or proposes new entries here under answer form (b).

## Schema

Every entry uses the same six fields:

- **ID.** `FM-NNN` ascending. Never recycled. Renaming an entry preserves the old ID.
- **Symptom.** What an operator or user observes when this failure manifests, in one or two sentences. Written so that a future session diagnosing a similar event can search the catalog by phenotype.
- **Root cause.** What in the system actually produced the symptom. Names mechanism, not blame.
- **Detection.** Where this class can be caught — which hook, agent, skill, or review step is in the position to surface it. If detection is purely behavioral today, say so explicitly so the gap is visible.
- **Prevention.** What stops the class at the source — the hook, rule, agent, template, or workflow that closes the loop. If prevention is partial or aspirational, say so honestly.
- **Example.** One sanitized concrete instance of the class, in generic terms.

## How to extend

When a new failure surfaces during a session:

1. Read this catalog top-to-bottom. If the failure phenotype matches an existing **Symptom**, extend that entry's Example list rather than create a new one.
2. If the root cause is a new class, append a new entry with the next `FM-NNN` ID. Use generic terms — no codenames, no real names, no real incident dates tied to a specific product, no absolute paths containing usernames.
3. Update **Detection** and **Prevention** if the new instance reveals a new way to catch or stop the class.
4. Reference the catalog entry from any related rule, hook, or agent change in the same commit.

The diagnosis rule (`rules/diagnosis.md`, "After Every Failure: Encode the Fix") makes this an explicit step in the post-failure workflow. The `harness-lesson` and `why-slipped` skills check this catalog first before proposing a brand-new mechanism.

---

## FM-001 — Concurrent-session plan wipe

- **Symptom.** A plan file in `docs/plans/` that existed and contained substantive content earlier in a session is empty, missing, or reverted to a stub when read later. The session that authored the plan has no edit in its history that explains the change.
- **Root cause.** A second concurrent Claude Code session (often a sub-agent build, a UX testing run, or a parallel orchestration thread) overwrote or replaced the plan file's contents because the in-flight version was not yet committed to git. The shared filesystem has no per-session locking; whichever session wrote last won.
- **Detection.** `plan-lifecycle.sh` PostToolUse hook surfaces a loud `[plan-uncommitted-warn]` warning when a new plan file is written but not yet committed. `pre-stop-verifier.sh` re-warns at session end if uncommitted plans remain. Neither blocks; both raise the chance the author commits before the wipe-out.
- **Prevention.** Commit the plan file in the same edit cycle that creates it, before any sub-agent dispatch or parallel work begins. Treat an uncommitted plan as transient state at risk from any concurrent activity. The `planning.md` "Plan File Lifecycle" section codifies this as the creation stage discipline.
- **Example.** A plan was authored and saved to `docs/plans/<slug>.md`, then the orchestrator dispatched a UX testing sub-agent on a different surface. The sub-agent's filesystem activity coincided with a separate orchestrator pass that re-templated the plan path, leaving the original plan empty. The work was reconstructed from conversation transcript only because the session was still open.

## FM-002 — Mysterious effort-level reset

- **Symptom.** A session that began at one configured effort level (`high` or `xhigh`) is observed mid-session running at a lower effort (`medium` or `low`), without any user-visible setting change. The agent's reasoning quality, tool-call density, and willingness to verify drop accordingly.
- **Root cause.** Effort level is read from `settings.json` and is not re-validated mid-session against the user's declared minimum. If a hook, plugin, or background process rewrites `settings.json` during the session — or if a sub-agent inherits a different config path — the effort level can shift silently. The session has no in-context audit of "what effort level am I currently at?"
- **Detection.** `effort-policy-warn.sh` runs at SessionStart and warns when the configured effort is below the project-level (`.claude/effort-policy.json`) or user-level (`~/.claude/local/effort-policy.json`) declared minimum. There is no mid-session detector — the warning is start-time only, so a mid-session drop is invisible until the next SessionStart.
- **Prevention.** Declare a minimum effort level in `~/.claude/local/effort-policy.json` so that any future SessionStart catches drift. The shipped `settings.json.template` declares `effortLevel: "max"` as the default for fresh installs so that the failure mode is structurally rare. Mid-session detection remains an open gap; the partial mitigation is operator awareness via the SessionStart warning.
- **Example.** An automation task ran for an extended period at what appeared to be reduced reasoning capacity. Subsequent inspection of `settings.json` at session end showed the effort level had been changed during the session. The automation's outputs from the affected window had to be re-evaluated.

## FM-003 — Bug-persistence trigger fired without persistence

- **Symptom.** During a session, the agent uses a trigger phrase that signals a bug or gap was identified ("we should also build X", "as a follow-up", "this is missing", "for next session") — but no `docs/backlog.md` entry, `docs/reviews/YYYY-MM-DD-*.md` file, or plan-evidence-log update is written before session end. The next session has no record that the gap was ever observed.
- **Root cause.** Identifying a bug and persisting a bug are separate operations. The agent's working memory holds the observation while it continues the current task, and "I'll write it down later" loses the observation when context shifts. Without a persistence step in the same response as the observation, the gap evaporates.
- **Detection.** `bug-persistence-gate.sh` Stop hook scans the session transcript for trigger phrases. If matches exist AND no change to `docs/backlog.md` or new `docs/reviews/YYYY-MM-DD-*.md` file is present in the working tree or recent commits, the hook blocks session end. Escape hatch: a `.claude/state/bugs-attested-YYYY-MM-DD-HHMM.txt` file with per-match justification documents legitimate false positives.
- **Prevention.** The `testing.md` "Bug Persistence" rule mandates writing the backlog or review entry in the same response as the observation, not later. The trigger-phrase list in the rule mirrors the patterns the Stop hook scans. The gate makes the rule mechanical: forgetting to persist is caught at session end, not lost.
- **Example.** A session investigating a workflow surfaced approximately two dozen distinct issues across state machine integration, harness gaps, and prompt content. Most were mentioned in conversation but not written to the backlog. The list had to be reconstructed retroactively from chat history, with high risk of omission. After this rule landed, the same class of session writes each gap to the backlog as it is observed.

## FM-004 — Verbose plan with placeholder-only required sections

- **Symptom.** A plan file in `docs/plans/` has all seven required headings (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy) but one or more sections contain only `[populate me]`, `TODO`, `...`, or template-default placeholder text. The plan reaches the implementation stage with hidden gaps.
- **Root cause.** The required-section structure was treated as a checklist of headings rather than a checklist of substance. The author copied the template, filled the easy sections (Goal, Tasks), and left the harder ones (Assumptions, Edge Cases) as placeholders intending to fill them later. The builder then started building against an under-specified plan.
- **Detection.** `plan-reviewer.sh` Check 6b enforces both presence (the heading must exist) and substance (each required section must contain at least 20 non-whitespace characters of non-placeholder content). Sections consisting solely of placeholder tokens are rejected at pre-commit time.
- **Prevention.** The `templates/plan-template.md` ships with prompts in each placeholder explaining what the section should contain, raising the friction of leaving them empty. The `verbose-plan` skill exists to fill gaps in thin plan files before commit. The mandatory rule in `planning.md` ("Verbose Plans Are Mandatory") makes the substance requirement explicit — empty Assumptions on a "trivial" plan is exactly the case where the section is most valuable.
- **Example.** A plan file was authored with all seven headings populated except Assumptions, which contained only `[populate me]`. The pre-commit gate blocked the commit; the author added two real assumptions ("the existing API behaves as documented", "the feature flag is enabled in the target environment") and the plan passed. Both assumptions turned out to be load-bearing during implementation.

## FM-005 — Untracked plan file location ambiguity

- **Symptom.** A hook, agent, or session looks for a plan file by slug at `docs/plans/<slug>.md` and reports "plan not found" — but the file exists at `docs/plans/archive/<slug>.md` because it has already transitioned to a terminal status. Verification, completion reports, or reminder hooks fail with a misleading error.
- **Root cause.** The plan-file lifecycle moves plans from `docs/plans/<slug>.md` to `docs/plans/archive/<slug>.md` when their `Status:` transitions to a terminal value (COMPLETED, DEFERRED, ABANDONED, SUPERSEDED). Callers that hard-code the active path don't find the file post-archive. Without an archive-aware resolver, every consumer has to re-implement the fallback.
- **Detection.** Symptom is observable via "plan not found" messages from hooks and agents. The `find-plan-file.sh` helper emits a `resolved from archive: <path>` stderr note when the match comes from the archive subdirectory, making archive-aware lookups explicit.
- **Prevention.** Use `~/.claude/scripts/find-plan-file.sh <slug>` for any code path that resolves a plan by slug. The script prefers active and falls back to archive transparently. Hooks and agents that previously hard-coded `docs/plans/<slug>.md` were migrated to the helper as part of the 2026-04-23 plan-lifecycle work. Hooks intentionally NOT made archive-aware (`pre-commit-gate.sh`, `backlog-plan-atomicity.sh`, `harness-hygiene-scan.sh`, `plan-edit-validator.sh`) are scoped to active-work enforcement; documenting that exception is part of the prevention strategy.
- **Example.** A post-tool reminder hook checked `docs/plans/<slug>.md` for an unchecked task matching an edited source file. After the plan was archived on completion, the hook stopped firing for any continuing edits — the slug no longer resolved at the active path. Migrating the hook to the archive-aware helper restored the reminder behavior without breaking active-plan semantics.

## FM-006 — Self-reported task completion without evidence

- **Symptom.** A plan task's checkbox is flipped from `- [ ]` to `- [x]` in the plan file, but no corresponding evidence block exists in the companion `<plan>-evidence.md` file, or the evidence block contains only plain-text manual verification ("checked in browser", "verified manually") with no replayable command.
- **Root cause.** Self-report failure mode: the builder marks its own work complete based on "I think this works" or "tests pass locally" without producing reproducible evidence that the user-observable outcome was exercised. Pre-Gen-4, the only enforcement was social — the builder was expected to be honest. In practice, multi-task plans accumulated checked tasks where the work was incomplete or untested.
- **Detection.** Three layers. (a) `plan-edit-validator.sh` PreToolUse hook blocks the checkbox flip unless a fresh evidence file with matching Task ID and a `Runtime verification:` entry exists within a 120-second window. (b) `runtime-verification-executor.sh` Stop-hook check actually executes every `Runtime verification:` entry — fakeable text fails. (c) `runtime-verification-reviewer.sh` Stop-hook check verifies the verification command corresponds to the modified files (curl URL hits a modified route, sql queries a modified table, test imports a modified source).
- **Prevention.** The `task-verifier` agent is the only entity authorized to flip checkboxes; it follows the evidence-first protocol enforced by `plan-edit-validator.sh`. The `planning.md` "Task Completion — Verifier Mandate" section makes this a hard rule. Plain-text manual verification is forbidden — every runtime task must produce a replayable command in one of five accepted formats (`test`, `playwright`, `curl`, `sql`, `file`).
- **Example.** A plan with 41 tasks was reviewed retrospectively; nine of the checked tasks were found to have no actual implementation matching the description. The builder had marked them complete based on "I built this earlier in the session" without re-verifying. The Gen 4 evidence-first protocol exists specifically to make this class structurally impossible — the validator can't be satisfied by intent alone.
