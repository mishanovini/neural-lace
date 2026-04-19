# Best Practices Encoded in Neural Lace

> **Status:** actively maintained. Every practice listed here is backed by a specific rule file, hook, or agent in the harness tree. If you find a reference that doesn't resolve, file an issue.

Neural Lace is more than an AI harness. It encodes a set of software-engineering and AI-collaboration practices that an individual developer or team would otherwise have to discover independently over years of practice and failure. This document is the reader's guide to those practices: what they are, why they exist, how the harness enforces them, and when it is honest to bend them.

The document is structured so each practice has the same shape:

1. **The rule** — one crisp sentence.
2. **Why it exists** — the motivating problem, what goes wrong without it.
3. **How the harness enforces it** — a specific file in the tree.
4. **When to break it** — honest edge cases.
5. **Worked example** where the practice has high novelty.

The harness distinguishes between two kinds of enforcement:

- **Mechanism** — a hook, agent, or script that physically rejects or gates the wrong action. You can't skip it without deliberate effort.
- **Pattern** — a documented convention. You are expected to follow it; no hook detects deviation.

Both matter, but they are not the same thing. This document labels which is which, so readers can calibrate how much friction each rule adds.

## Table of contents

- [Core practices](#core-practices)
- [AI-collaboration practices](#ai-collaboration-practices)
- [Security practices](#security-practices)
- [Planning + decision practices](#planning--decision-practices)
- [Testing + verification practices](#testing--verification-practices)
- [Documentation practices](#documentation-practices)
- [Autonomy practices](#autonomy-practices)
- [Diagnosis practices](#diagnosis-practices)
- [UX practices](#ux-practices)
- [Commit practices](#commit-practices)
- [References](#references)
- [Contributing](#contributing)

---

## Core practices

These are the practices that shape the harness at its foundation. If you take nothing else from this document, take these three.

### Two-layer configuration — separate personal from shareable

**Classification:** Hybrid. The two-layer pattern is a documented convention; the "no sensitive identifiers in the shareable layer" ban is enforced mechanically by a pre-commit scanner.

**The rule.** Never commit personal identifiers, secrets, or machine-specific paths to a shareable harness repo. Personalization lives in a user-local layer (`~/.claude/local/`, gitignored); shareable defaults live in the harness layer (committed, generic).

**Why it exists.** A harness is a kit — something another person installs and uses. It is not a snapshot of one author's work. The moment a harness contains the author's email, employer, client codename, or absolute home-directory path, it stops being a kit and becomes a personal artifact that happens to be installable. Every future contributor has to strip or shadow the author's identity to use it. Over time this corrodes the kit from both directions: downstream users tolerate identity fragments because they don't know which are meaningful, and the upstream author starts leaving more of them in because nothing breaks when they do.

The two-layer model separates these concerns cleanly. Harness code is generic and shareable, with safe fallbacks. Local config (account names, project IDs, per-machine paths) lives in `~/.claude/local/*.config.json`, which the harness reads at runtime. If the local layer is missing or incomplete, the harness still runs with generic defaults — it does not crash, and it does not silently substitute a real identifier from elsewhere.

**How the harness enforces it.** `principles/harness-hygiene.md` documents the rule. `adapters/claude-code/hooks/harness-hygiene-scan.sh` runs as a pre-commit hook and blocks commits that match any pattern in `adapters/claude-code/patterns/harness-denylist.txt` — real email addresses, personal domains, employer names, codenames, absolute paths containing a username, common credential prefixes. The `harness-reviewer` agent (`adapters/claude-code/agents/harness-reviewer.md`) provides a second adversarial pass that catches stylistic leaks the denylist doesn't cover.

**When to break it.** You don't. This rule has no legitimate exceptions for harness code. The only allowed use of a real name anywhere in the harness tree is a clearly-labeled `Owner:` or `Maintainer:` field at the top of a document — an attribution, not an embedded identifier. If you believe you need to bend this rule, the correct action is to split the value into the local layer instead.

**Worked example.**

```bash
# Harness layer (committed): adapters/claude-code/hooks/session-start.sh
# Read account name from local config with generic fallback.
ACCOUNT_NAME="$(jq -r '.default_account // "personal"' \
  "$HOME/.claude/local/accounts.config.json" 2>/dev/null || echo "personal")"

# Local layer (gitignored): ~/.claude/local/accounts.config.json
{
  "default_account": "<your-account-name>",
  "accounts": {
    "<your-account-name>": {
      "github_user": "<your-github-handle>",
      "public_blocked": true
    }
  }
}
```

The harness layer reads generically; the real identifiers live in a file the harness never commits.

### CLAUDE.md < 200 lines — index, not a book

**Classification:** Pattern. Not hook-enforced; encoded by how `CLAUDE.md` itself is organized.

**The rule.** Keep `CLAUDE.md` a terse index that points at detailed rule files under `rules/`. The informal ceiling is ~200 lines. Detailed content lives in topic-owning rule files, not in `CLAUDE.md` itself.

**Why it exists.** `CLAUDE.md` is loaded into every Claude Code session as the first context the model sees. Every byte in that file consumes budget that otherwise goes to the user's actual problem. A 2,000-line `CLAUDE.md` crowds out the files the model needs to read to answer the question. Worse, long context at the top of the window is exactly the place where drift, false memories, and subtle hallucinations accumulate — the model may "remember" a rule that isn't there, or forget one that is.

Keeping `CLAUDE.md` under ~200 lines forces discipline: each topic (planning, testing, security, UX) gets its own rule file. The rule files are loaded only when relevant — the `/rules:testing` skill or an explicit reference pulls them in. The index stays stable; the detail stays available.

**How the harness enforces it.** The shipped `adapters/claude-code/CLAUDE.md` models the pattern — a short top-level file with pointers to `rules/planning.md`, `rules/testing.md`, `rules/security.md`, and so on. The pattern is self-applied; a contributor who piles detail into `CLAUDE.md` will notice the file growing, but nothing will reject their commit.

**When to break it.** Small projects with fewer than ~5 topical areas may not need the split — a 300-line `CLAUDE.md` can be fine for a tiny repo where there isn't enough material to warrant separate rule files. The ceiling is a heuristic, not a law. The underlying principle — "don't put into `CLAUDE.md` what you can put into a focused rule file" — still applies.

### Orchestrator pattern — multi-task plans delegate to sub-agents

**Classification:** Pattern. Self-applied. Not hook-enforced; the `tool-call-budget` and `pre-stop-verifier` hooks create indirect pressure toward dispatching, but no hook detects "main session built directly instead of delegating."

**The rule.** For any plan with more than one task, the main session orchestrates and dispatches build work to `plan-phase-builder` sub-agents — preferring parallel dispatch when tasks are independent — and does NOT do the build work itself.

**Why it exists.** Context accumulates. A plan with eight phases runs 200+ tool calls of raw file reads, edits, test output, and bash results. All of that context sits in the main session's window for the rest of the session. At that size, two things degrade: speed (every prompt gets slower) and quality (drift from early instructions, false memories of work not done, subtle hallucinations).

Sub-agents get fresh context per dispatch. The builder of Phase 3 starts clean, unaware of Phase 1's 40 tool calls. The orchestrator's context only grows by the dispatch prompt + the builder's short return — typically 500 tokens, not 50,000.

**Honest caveat.** This pattern is a quality-of-life improvement for long plans; it is NOT the load-bearing defense against the specific vaporware failures that shaped Gen 4 of this harness. Those failures (plan checkboxes flipped without builds, tests passing without runtime verification) were failures of *verification*, not of *context size*. The hook-backed Gen 4 mechanisms — `pre-commit-tdd-gate.sh`, `plan-edit-validator.sh`, `runtime-verification-executor.sh` — address those directly. The orchestrator pattern layers on top of those, not in place of them.

**How the harness enforces it.** `adapters/claude-code/rules/orchestrator-pattern.md` documents the dispatch contract, the parallel-vs-serial decision, the cherry-pick-and-verify-sequentially protocol, and the anti-patterns. `adapters/claude-code/agents/plan-phase-builder.md` is the sub-agent implementation. The plan template declares `Execution Mode: orchestrator` by default for multi-task plans.

**When to break it.** Single-task quick fixes ("rename this function", "fix this typo") don't need orchestration — the overhead of a dispatch outweighs the context benefit. Doc-only edits usually don't either. Interactive bug-hunt sessions where the user wants to reason alongside the main session also bypass this pattern, because the user is giving context to the main session directly. The rule applies to long autonomous plans, not to every single task.

**Worked example.**

```
Plan: refactor all 12 dashboard pages to use the new data-table component.

Anti-pattern: main session edits all 12 pages sequentially. By page 6,
context contains 12 large file reads + 30 test runs. Quality degrades on
pages 7-12.

Pattern: dispatch 5 builders in parallel (isolated worktrees) for pages
1-5. Collect results. Cherry-pick each commit onto the feature branch.
Run task-verifier once per task. Dispatch next 5. And so on.

Main session's context grows by 12 short return messages, not 12 file
edits.
```

---

## AI-collaboration practices

These practices shape the handoff between human judgment and AI execution. The harness was rebuilt around these after a series of vaporware failures in 2026-04 where the AI claimed completion for work that wasn't done.

### Evidence-based task completion — no self-reporting

**Classification:** Mechanism. The `plan-edit-validator.sh` hook rejects any plan-file edit that flips a checkbox without a matching fresh evidence block.

**The rule.** Plan checkboxes (`- [ ]` → `- [x]`) may only be flipped by the `task-verifier` agent. The builder never edits their own checkbox.

**Why it exists.** Self-reporting has failed in practice. Every generation of the harness that trusted the builder's claim of "done" eventually shipped something half-built. The specific failure pattern: a builder finishes the code, thinks it looks correct, flips the checkbox, moves on. No one tests the feature at runtime. It ships. Users hit the broken path. Trust erodes.

The fix is structural. A separate agent — `task-verifier` — takes the task's acceptance criteria and independently checks them: reads the files, runs the typecheck, greps for expected patterns, queries APIs, takes screenshots. Only if the verifier's checks pass does the checkbox flip and the evidence block land in the plan's `## Evidence Log`. The verifier has no stake in the task being marked complete; it has the opposite — it is instructed to err toward FAIL.

**How the harness enforces it.** `adapters/claude-code/agents/task-verifier.md` defines the verifier's contract (inputs, required checks, output shape). `adapters/claude-code/hooks/plan-edit-validator.sh` runs on every edit to a plan file under `docs/plans/` and rejects edits that flip a checkbox without a corresponding fresh evidence block in the same file. `adapters/claude-code/hooks/pre-stop-verifier.sh` runs at session end and blocks termination if any checked task lacks a valid evidence block.

**When to break it.** Never mechanically. The hook has no override. If you need to mark a task complete without a verifier run, the legitimate paths are: set plan `Status: ABANDONED` (with reason), set plan `Status: DEFERRED` (with resume conditions), or un-scope the task by editing the plan's task list to remove it. The last path requires explaining why in the plan's Decisions Log.

**Worked example.**

```
Builder finishes task 3.2: "Add notify-managers button to contact-review page."

WRONG:
  builder edits plan: - [ ] 3.2 → - [x] 3.2
  builder appends to Evidence Log: "Done. Button added."
  plan-edit-validator REJECTS the commit; hook exits 1.

RIGHT:
  builder invokes task-verifier via Task tool with:
    - Plan path, task ID, files modified, acceptance criteria
  task-verifier reads the files, runs the typecheck, greps the JSX
  for the button, checks the handler wires to the correct API route,
  runs a Playwright screenshot.
  task-verifier returns PASS and writes the evidence block itself.
  checkbox flips; commit succeeds.
```

### Anti-vaporware — mechanical verification of runtime behavior

**Classification:** Mechanism. Multiple hooks enforce the requirement that runtime features have runtime verification, not just static code review.

**The rule.** Runtime features (UI, API, webhooks, migrations, cron) must have runtime verification entries in the plan's Evidence Log — replayable commands that exercise the feature end-to-end and produce artifacts (response body, screenshot, query result). "Typecheck passed" is not verification. "The code exists" is not verification.

**Why it exists.** On 2026-04-14 this harness shipped four features that the AI claimed complete and the user discovered broken. In each case the pattern was the same: code was written, typechecks passed, tests (which mocked the failing dependency) passed, the task checkbox flipped, and the feature didn't work at runtime. An API route 500'd because a migration column was missing. A dashboard page returned zero rows because the impersonation-aware query filter was broken. A hold-for-review guard protected a pipeline that was never wired up. And a "per-contact hold toggle" described in conversation simply didn't exist in code.

The common failure: self-enforced rules. "I should test at runtime" is a prose instruction that an AI under time pressure will quietly skip. The postmortem conclusion was that anti-vaporware enforcement must be hook-executed — mechanical gates that refuse to let a commit land, a checkbox flip, or a session end until runtime verification has actually happened and its artifacts are present in the evidence block.

**How the harness enforces it.** `adapters/claude-code/rules/vaporware-prevention.md` documents the full enforcement map. Key hooks:

- `adapters/claude-code/hooks/pre-commit-tdd-gate.sh` — four layers. Layer 1-2 scans the staged diff and rejects new/modified runtime files without tests. Layer 3 rejects integration tests that mock the system under test. Layer 4 rejects tautology assertions (`expect(true).toBe(true)`, `expect(x || true).toBe(true)`).
- `adapters/claude-code/hooks/runtime-verification-executor.sh` — parses the plan's evidence-block runtime-verification entries as replayable bash commands, runs them, and captures the output.
- `adapters/claude-code/hooks/runtime-verification-reviewer.sh` — cross-checks that the runtime verification entries correspond to the feature described in the task (a UI task needs a screenshot, an API task needs a curl response body, a migration task needs a schema/data query).
- `adapters/claude-code/hooks/plan-reviewer.sh` — invoked from the pre-commit-gate; rejects plan files that describe runtime features without runtime-verification specs.

**When to break it.** Pure-refactor tasks that don't change behavior can rely on tests alone. Doc-only tasks can skip runtime verification. Tasks that only modify build config (eslint rules, tsconfig paths) can skip it. Any task that changes user-observable behavior at any system boundary requires runtime verification, no exceptions.

**Worked example.**

```
Task: "API route POST /api/contacts accepts a new contact and returns 201."

Plan evidence-block runtime verification spec:
  RUNTIME_VERIFICATION:
    - cmd: curl -s -X POST http://localhost:3000/api/contacts \
        -H "Content-Type: application/json" \
        -d '{"name":"Jane Doe","email":"jane@example.com"}' \
        -w "\nHTTP %{http_code}\n"
      expect: HTTP 201 and response body contains "id"

runtime-verification-executor runs this command, captures output:
  {"id":"abc-123","name":"Jane Doe","email":"jane@example.com"}
  HTTP 201

Evidence block includes the captured output. Without this block, the
commit is rejected.
```

### Tool-call budget — forced pause every 30 calls

**Classification:** Mechanism. `tool-call-budget.sh` runs as a PreToolUse hook and blocks the next tool call every 30 Edit/Write/Bash invocations until an audit is acknowledged.

**The rule.** After every 30 tool calls from the Edit/Write/Bash family, the harness blocks the next tool call. Proceeding requires invoking `plan-evidence-reviewer` to audit progress so far and producing a sentinel acknowledgment file.

**Why it exists.** Attention degrades in long sessions. Without an external forcing function, the AI tends to accumulate small drifts — a stale assumption here, a forgotten constraint there — that aren't visible until the final result is wrong. Thirty calls is roughly the point where "I'm sure I'm on track" starts to be unreliable. A forced pause with an independent audit (the `plan-evidence-reviewer` agent reads the plan, the staged diff, and the evidence log, then reports what's actually been done vs. claimed) catches drift before it compounds.

The 30-call threshold is heuristic. Shorter thresholds add too much friction. Longer thresholds let drift accumulate. Thirty has held up across long autonomous plans in practice.

**How the harness enforces it.** `adapters/claude-code/hooks/tool-call-budget.sh` counts Edit/Write/Bash calls per session and blocks call #31, #61, #91, ... until `~/.claude/state/reviews/` contains a fresh review file with the required sentinel lines (`REVIEW COMPLETE` + `VERDICT:`). The `plan-evidence-reviewer` agent produces those files when invoked.

**When to break it.** You don't, mechanically. The hook always blocks. What you can choose is whether the review is thorough or perfunctory — under time pressure it's tempting to produce a drive-by review that satisfies the sentinel without actually catching drift. That's a self-defeat; the reviewer exists because the builder already thinks things are fine.

**Known gap.** The `--ack` attestation is not cryptographically protected. A builder could in principle write a sentinel file directly without invoking `plan-evidence-reviewer`. Friction is raised (the bypass requires knowing the file format and writing a plausible review body), but the gate isn't fully closed. See the "Missing from enforcement map" section of `adapters/claude-code/rules/vaporware-prevention.md`.

### Automation mode — opt-in autonomy

**Classification:** Mechanism. `automation-mode-gate.sh` runs as a PreToolUse hook on commands matching the deploy-class matcher.

**The rule.** The default automation mode is `review-before-deploy`. Claude pauses before any command matching a deploy-class matcher (`git push`, `gh pr merge`, `vercel deploy`, `supabase db push`, etc.). Users opt IN to `full-auto` via `/automation-mode full-auto` or by editing `~/.claude/local/automation.config.json`.

**Why it exists.** Autonomy is powerful but irreversible operations must have a human in the loop by default. A force-push, a production deploy, a merged PR, a migration on prod — these can't be quietly undone if the AI was confused. Making `full-auto` the default would mean users opt OUT of safety to get safety, which is the wrong polarity.

`review-before-deploy` inverts that: the safe default is a pause, and the user explicitly chooses to remove it for contexts where they've built trust (their own sandbox, a scratch repo, a long autonomous plan they've reviewed). When `full-auto` is on, the gate still logs the operation but doesn't pause.

**How the harness enforces it.** `adapters/claude-code/hooks/automation-mode-gate.sh` checks the current mode (from `~/.claude/local/automation.config.json`) and either blocks-with-prompt or logs-and-proceeds. `adapters/claude-code/commands/automation-mode.md` is the `/automation-mode` slash command that toggles the setting.

**When to break it.** You don't break this rule; you choose a setting. `full-auto` is appropriate for a long autonomous plan where the user has reviewed the plan in detail and trusts the dispatch. `review-before-deploy` is appropriate for everything else, including bug-hunt sessions, ad-hoc work, and first-time usage of a new plan.

---

## Security practices

Security in a harness is largely about what must never ship in committed code. These rules are unusually strict because harnesses are copy-paste-scale artifacts: one leaked credential in a harness template becomes a leaked credential in every downstream project.

### No secrets in harness code — ever

**Classification:** Mechanism. `harness-hygiene-scan.sh` runs pre-commit and matches against `harness-denylist.txt` patterns.

**The rule.** No passwords, tokens, API keys, real emails, personal domains, employer names, or product codenames may appear in any file committed to a harness repo. Not in comments, not as fallback defaults, not in example fixtures, not in rule bodies, not in tests.

**Why it exists.** Placeholders get copy-pasted into real usage. Real credentials get pasted back into "placeholder" slots. The only safe rule is: no real identifiers, ever, anywhere in committed harness code.

This rule is grounded in a concrete failure. A harness's own `verify-ui.mjs` template once contained a hardcoded test-password fallback — something like `password: 'test123'` as a default when no env var was set. That fallback got copy-pasted into a downstream project's test-user creation script. The test user was created with the literal string `'test123'` as its production password. The string originated in the harness template; it ended up in a production auth system.

The lesson: even "obviously fake" placeholder values in harness code are dangerous, because they travel by copy-paste faster than the reader's judgment about which ones are real. The safe rule is zero tolerance — use visibly-bracketed placeholders (`<your-password>`, `<your-api-key>`) that fail loudly when pasted unchanged.

**How the harness enforces it.** `principles/harness-hygiene.md` documents the rule in full. `adapters/claude-code/hooks/harness-hygiene-scan.sh` runs as a pre-commit hook, reads the denylist at `adapters/claude-code/patterns/harness-denylist.txt`, and rejects commits matching any pattern. The `harness-reviewer` agent provides adversarial review for stylistic leaks the denylist doesn't cover. A planned `/harness-review` skill (partially implemented) runs weekly full-tree scans.

**When to break it.** Never. Every exception proposed over the harness's lifetime has ended with "yes but — " and then a lesson about why the exception was a mistake. If a value needs to be real, it goes in the local layer (`~/.claude/local/`), which is gitignored and never shipped.

**Worked example.**

```
WRONG (harness layer):
  # adapters/claude-code/hooks/session-start.sh
  DEFAULT_EMAIL="<someone>@<real-employer>.com"  # "placeholder"

  harness-hygiene-scan REJECTS: real-looking email domain not in allowlist.

RIGHT:
  # adapters/claude-code/hooks/session-start.sh
  DEFAULT_EMAIL="<your-email>"  # populated from ~/.claude/local/personal.config.json

  # ~/.claude/local/personal.config.json (gitignored, user-specific)
  { "email": "<your-real-email-here>" }
```

### Pre-push credential scanner — every push, every repo

**Classification:** Mechanism. Installed globally via `git config --global core.hooksPath`; runs on every `git push` in every repo the user has on their machine.

**The rule.** A credential-pattern scanner runs on every `git push`, in every repo. Eighteen-plus credential families are blocked by default (AWS keys, GitHub PATs, Stripe keys, Twilio auth, Supabase service-role keys, Anthropic keys, OpenAI keys, Google service-account JSON, private-key PEM blocks, JWT-shaped secrets). Teams extend the pattern set via `~/.claude/business-patterns.d/*.txt`.

**Why it exists.** Credentials should never reach a remote. The pre-push scanner is the last-line defense when pre-commit checks were missed, when `.gitignore` was wrong, when a secret was committed and then "fixed" by a follow-up commit (leaving it in history), when a user pastes a secret into a chat log that's checked in. It is not the primary defense — `.gitignore` + code review + secret scanning in the remote host all come first — but it catches slip-throughs.

The scanner is installed globally (not per-repo) because per-repo installation is unreliable. Users forget. Fresh clones don't carry hooks by default. A global `core.hooksPath` ensures the scanner runs even in repos the user just cloned ten seconds ago.

**How the harness enforces it.** `adapters/claude-code/hooks/pre-push-scan.sh` is the scanner itself. `install.sh` wires it globally by setting `git config --global core.hooksPath` to the harness hooks directory. The scanner reads both a committed default pattern list and optional user-extended pattern files from `~/.claude/business-patterns.d/`.

**When to break it.** Very rarely. If a pattern produces a false positive on a push you must make, the right response is: (a) confirm it's genuinely a false positive, (b) narrow the pattern in `harness-denylist.txt` to exclude this case, (c) commit the pattern fix, (d) re-push. The wrong response is `git push --no-verify`, which silently bypasses the scanner. See "Never skip hooks" under commit practices.

### Account-aware public-repo block

**Classification:** Mechanism. A PreToolUse hook matches `gh repo create` and `gh repo edit --visibility` commands and rejects them when the current account is marked `public_blocked: true`.

**The rule.** When the current account has `public_blocked: true` in `~/.claude/local/accounts.config.json`, all public-repo creation and visibility-change operations are blocked at the harness layer. The block pairs with GitHub's org-level setting but fires earlier in the pipeline.

**Why it exists.** Public is a one-way door. Once a repository's history is public, GitHub retains it, scrapers index it within minutes, and "scrub and make private" does not remove the public record. For a work account or any account tied to non-public business code, accidental public creation can't be quietly undone.

Org-level settings on GitHub provide one layer of defense, but they are not universally available (personal accounts don't have them in the same form), and they fire at API time — after the harness has already issued the request. A local block fires before the request is ever made, which is cheaper and covers cases the server-side setting misses.

**How the harness enforces it.** `adapters/claude-code/settings.json.template` wires a PreToolUse hook that parses Bash invocations matching `gh repo create` (without `--private`) or `gh repo edit --visibility public` and rejects them when the active account's config has `public_blocked: true`. The account is resolved from working directory (`~/claude-projects/<org>/` → account name) via the same logic the session-start hook uses.

**When to break it.** When the user explicitly asks in the current message to create a public repo, AND the current account is not `public_blocked`, AND a full security audit has confirmed the repo is safe to publish. The block is not a suggestion to pause — it's a refusal to act. Removing `public_blocked: true` from a work account's config is a decision the user must make deliberately.

### Decision records for Tier 2+ — mechanical atomicity

**Classification:** Mechanism. `decisions-index-gate.sh` runs pre-commit and rejects commits where a new `docs/decisions/NNN-*.md` file is staged without a corresponding update to `docs/DECISIONS.md`, or vice versa.

**The rule.** Every Tier 2 or Tier 3 decision (see [Tier classification](#tier-classification-for-mid-build-decisions)) requires a standalone `docs/decisions/NNN-<slug>.md` record committed in the same commit as the implementation. An index `docs/DECISIONS.md` tracks all records by number + slug + one-line summary. The gate hook enforces atomicity: you cannot add a decision file without updating the index, and you cannot update the index without the corresponding file.

**Why it exists.** Decisions lose context fast. A short "we chose X because Y" entry in a plan file's Decisions Log disappears from view the moment the plan is archived. Six months later, a future session (human or AI) looks at the code, wonders why a choice was made, and has no trail to follow. They re-derive the reasoning from git history and code reading, and often get it wrong — leading to a second decision that contradicts the first, or an "improvement" that undoes the original rationale.

A dedicated `docs/decisions/NNN-*.md` record survives plan archival. The index `docs/DECISIONS.md` provides navigability (by number, by title, by date, by status). Together they form a permanent reasoning trail that outlasts any single plan.

The atomicity gate matters because without it, records and indexes drift. Someone adds a record without updating the index; someone updates the index with a number that points at a missing file; someone renames a slug but forgets the index. The gate rejects any commit where the two drift apart.

**How the harness enforces it.** `adapters/claude-code/rules/planning.md` documents when a decision record is required (every Tier 2+ choice). `adapters/claude-code/hooks/decisions-index-gate.sh` runs pre-commit on the harness repo and on project repos that opt in; it verifies that staged changes to `docs/decisions/` and `docs/DECISIONS.md` are consistent.

**When to break it.** Tier 1 decisions (trivial, isolated, reversible) do NOT need decision records. A one-line fix for a typo, a rename of a local variable, a comment clarification — none of these are Tier 2. The threshold is: "could a reasonable person six months from now wonder why this was done?" If yes, it's Tier 2. If no, it's Tier 1.

**Worked example.**

```
Tier 2 decision: choose between two API shapes for the new webhook endpoint.

Workflow:
  1. Discuss with user, pick shape A.
  2. Stage implementation files AND docs/decisions/042-webhook-api-shape.md
     (Context / Decision / Alternatives / Consequences) AND append one row
     to docs/DECISIONS.md pointing at 042.
  3. Commit.

If step 2 is split into two commits (record first, index later, or vice versa),
decisions-index-gate.sh REJECTS the commit that has one without the other.
```

---

## Planning + decision practices

These practices shape how work is scoped, broken down, and steered mid-build. They are the connective tissue between "the user has an idea" and "the feature ships correctly."

### Planning before building, completeness over speed

**Classification:** Pattern. Self-applied, but the task-verifier mechanism and the `pre-stop-verifier` session-end check create strong pressure in this direction.

**The rule.** For any task involving architectural decisions, non-obvious multi-file interactions, or expected work > ~15 minutes, enter plan mode before building. Write a plan file at `docs/plans/<descriptive-slug>.md` following the template. Surface decisions with alternatives and a recommendation. Only start implementing after ambiguities are resolved.

A stronger companion rule applies at execution time: **never prioritize speed over completeness.** Scope is mechanical — it is whatever is in the plan file's task list. An unchecked task is in scope. Deferral is only legitimate when a task is dependency-blocked or the user explicitly deferred it in the current session. "I want to finish faster" or "the minimum viable version is enough" are not legitimate reasons to drop a scoped task.

**Why it exists.** The quality of a plan determines the quality of execution. Planning is where human judgment matters most — tradeoffs get weighed, alternatives get surfaced, edge cases get identified. Building is where autonomy matters most — once the plan is good, the AI can execute with minimal interruption. Collapsing planning into building produces plans that are actually just the AI's first guess, and builds that can't be verified because the acceptance criteria never existed.

The "completeness over speed" half addresses a different failure: autonomous sessions that cut scope to finish faster. A user granting autonomous execution is authorizing the AI to work without pausing — they are NOT authorizing it to decide mid-run that task 7 of 10 is "polish" and can be skipped. Scope is the plan's task list, not the AI's interpretation of which tasks matter.

**How the harness enforces it.** `adapters/claude-code/rules/planning.md` is the full protocol. `adapters/claude-code/templates/plan-template.md` is the starting shape. `adapters/claude-code/hooks/pre-stop-verifier.sh` blocks session termination if an active plan has unchecked tasks and `Status` is not one of `COMPLETED`, `DEFERRED`, or `ABANDONED`. This forces explicit disposition — you cannot silently abandon work at session end.

**When to break it.** Simple single-file changes, bug fixes with obvious solutions, and doc-only edits don't need plan files. The 15-minute heuristic is a floor, not a ceiling. For anything above that threshold, or anything involving decisions that would be painful to undo, plan first. Speed is real but it is purchased from the wrong budget when it comes from skipping the plan.

### Tier classification for mid-build decisions

**Classification:** Pattern. Self-applied; the tier choice drives whether a decision record is required (which is mechanism-enforced via `decisions-index-gate.sh`).

**The rule.** Classify every mid-build decision by reversibility:

- **Tier 1** — isolated, trivially reversible. Continue + document in the plan's Decisions Log. No decision record required.
- **Tier 2** — multi-file, revertible. Commit a checkpoint first; continue; document with the checkpoint SHA; create a `docs/decisions/NNN-*.md` record.
- **Tier 3** — DB schema changes, public API changes, auth changes, production-data changes, or anything that is not quietly reversible. Pause. Document the tradeoffs and alternatives. Wait for explicit user approval before proceeding.

**Why it exists.** The cost of an unwanted irreversible action is much higher than the cost of pausing to confirm. Cost of pausing: ~5 minutes of user time to review and approve. Cost of a bad Tier 3 action taken without approval: hours to days of cleanup, potentially lost data, potentially user trust damage that doesn't come back.

The tier system exists to make this calculus explicit. An AI without tier discipline defaults to "I'll just do it" for every decision, because that minimizes immediate friction. The correct default for reversible choices (Tier 1) IS to just do it. The correct default for consequential choices (Tier 3) is the opposite. Naming the tiers forces the classification step.

**How the harness enforces it.** `adapters/claude-code/rules/planning.md` Mid-Build Decisions section describes each tier. The decisions-index-gate enforces the Tier 2+ record requirement. Tier 3 is self-applied — no hook can tell "you should have paused here" after the fact; the AI must make the call at decision time.

**When to break it.** You don't break the tiers; you calibrate them. A decision that looked Tier 1 but turned out to touch more files than expected gets re-classified to Tier 2 with a checkpoint commit. A Tier 2 decision that crosses into auth or schema territory gets re-classified to Tier 3 with a pause. The classification is a floor — "at least this tier" — not a ceiling.

**Worked example.**

```
Mid-build decision: the feature needs to store a new piece of state.
Options: (a) add a column to an existing table, (b) add a new table.

Tier analysis:
  - Adding a column is a Tier 3 decision (schema change on a populated
    table). Even though (a) looks "simpler," it is not quietly reversible
    — dropping a column after data has written to it loses that data.
  - Adding a new table is ALSO Tier 3 (new RLS surface, new backup
    implications, affects the seed_org_defaults function if org-scoped).

Both options are Tier 3. Pause, document both, wait for user approval.
Do NOT silently pick one based on "this is faster."
```

---

## Testing + verification practices

These practices ensure that "it works" is a statement backed by evidence, not a statement of confidence. They are the connective tissue between code and trust.

### Link validation + consistency audit — mechanical

**Classification:** Mechanism. Scripts run as part of the commit gate and explicitly as `npm run` targets.

**The rule.** Every commit that adds or modifies `href` values runs `npm run test:links` against the codebase. Every significant commit runs `npm run audit:consistency`, which scans for pattern violations: raw string formatting that should use shared helpers, unapproved colors (orange, yellow) not in the project palette, HTML entity arrows (`&larr;`) that should use icon libraries, `<h1>` in content pages, outline-only buttons that violate the "filled button" rule for dark mode, missing `loading.tsx` for server-component pages, and manual fallback chains that should use dedicated helpers.

**Why it exists.** These are the bugs that pass typecheck and pass tests but break in production. A dead internal link (`/insights` when the page is at `/ai-insights`) is a typecheck-clean string that 404s in the browser. An outline-only button passes its render test but is invisible in dark mode. A raw `.toLocaleString()` call in one file diverges from the project's shared formatter and produces inconsistent display. These failures are mechanical, which means they can be caught mechanically — not by a human reviewer who might miss them, but by a script that finds every instance.

**How the harness enforces it.** `adapters/claude-code/rules/testing.md` documents the cadence (link validation after any href change, consistency audit before every significant commit). Scripts live in each project's `scripts/` directory, copied from the harness's `adapters/claude-code/scripts/audit-consistency.ts` template. P0 and P1 violations block the audit (exit code 1); P2 is informational.

**When to break it.** When the script produces a false positive on a legitimate case, the correct response is to refine the script's rules (narrow the pattern, add an allowlist) rather than bypass it for the specific commit. When an href is deliberately external (a link to a third-party site), the link validator should skip it — and if it doesn't, that's a bug in the validator, not a reason to skip the check.

### UX validation after substantial builds — three audience-aware agents

**Classification:** Pattern. Self-applied; the agents must be invoked by the builder or orchestrator after any substantial UI work.

**The rule.** Run `ux-end-user-tester`, `domain-expert-tester`, and `audience-content-reviewer` after any new feature, page redesign, or workflow change. All P0 (blocking) and P1 (confusing/frustrating) findings must be fixed. P2 (polish) may be deferred.

Each agent plays a distinct role:

- `ux-end-user-tester` walks the feature as a generic non-technical user — someone who knows nothing about the internal model and reads only what the screen says.
- `domain-expert-tester` reads `.claude/audience.md` to adopt the project's target persona (HVAC contractor, personal finance user, etc.) and tests workflows from that persona's perspective, calling out jargon, missing mental models, or workflow breaks specific to that audience.
- `audience-content-reviewer` reads all user-facing text and flags wrong-audience language, technical jargon that leaks into user-facing copy, and empty/placeholder content.

**Why it exists.** UX issues found in production cost roughly ten times what UX issues found in testing cost, which themselves cost ten times what UX issues found in design cost. The agents catch issues at test time — still cheap — but specifically the kinds of issues that a builder staring at their own code is worst at catching. A builder knows what the code is supposed to do. A first-time user doesn't, and stumbles on things the builder never sees.

The three-agent split matters because one agent can't be three personas. An all-purpose "UX review" collapses into generic criticism. Three focused agents produce three focused critiques: generic-user friction, domain-specific workflow fit, and content voice.

**How the harness enforces it.** `adapters/claude-code/rules/testing.md` UX Validation section documents the cadence. The three agent files (`adapters/claude-code/agents/ux-end-user-tester.md`, `domain-expert-tester.md`, `audience-content-reviewer.md`) define the agent contracts. `.claude/audience.md` in each project carries the persona definition the domain-expert agent reads.

**When to break it.** Backend-only changes, pure-refactor tasks, doc updates, and bug fixes that don't change UI don't require UX agent runs. Small UI tweaks (a single button added to an existing form, a copy edit) may not need the full three-agent sweep — one focused pass may be enough. The trigger is "substantial builds" — new feature surfaces, new flows, anything that changes how a user accomplishes a task.

### Visual regression via screenshots — layout that matters

**Classification:** Pattern. Self-applied; the mechanism is Playwright's `toHaveScreenshot()` which each project wires into its test suite.

**The rule.** For pages where spatial layout matters (funnels, dashboards, detail panels, modals with multi-panel layout), use Playwright's `toHaveScreenshot()` to baseline-and-diff. Add a screenshot assertion after loading and after interacting with each meaningful state.

**Why it exists.** Structural tests — "the grid container has class `grid-cols-2`" — don't catch the failure they're supposed to catch. A grid class can apply to a container whose children render single-column because the children themselves lack the right width constraints. An SVG element can render on top of button text, making the button invisible even though the button is in the DOM. A responsive breakpoint can misfire, collapsing content at the wrong viewport. All of these pass structural assertions and fail at a glance in a screenshot.

Screenshot baselines catch layout bugs that structural assertions miss. They also catch regressions introduced by CSS changes elsewhere in the codebase — a change to a shared spacing utility that propagates to twelve pages you didn't test manually.

**How the harness enforces it.** `adapters/claude-code/rules/testing.md` documents when to add screenshot assertions. Playwright stores baselines locally in the project, no external service required. The `pre-commit-tdd-gate.sh` Layer 4 check for tautology assertions flags tests that claim to verify layout via `toHaveClass('grid-cols-2')` alone — a signal that a screenshot assertion should be added.

**When to break it.** Pages where spatial layout is not load-bearing (a simple form, a single-column settings page) don't need screenshot baselines. Pages that change visually every build (time-stamped content, randomized fixtures) need careful mask configuration or aren't good candidates. The rule applies to pages where "this looks right" is a meaningful acceptance criterion.

**Worked example.**

```typescript
// e2e/dashboard.spec.ts
test('dashboard renders hero cards and supporting grid', async ({ page }) => {
  await page.goto('/dashboard');
  await page.waitForSelector('[data-testid="kpi-grid"]');

  // Structural check: cards exist.
  await expect(page.locator('[data-testid="hero-card"]')).toHaveCount(2);

  // Visual regression: the layout actually renders correctly.
  await expect(page).toHaveScreenshot('dashboard-default.png');

  // Interactive state.
  await page.click('[data-testid="kpi-toggle"]');
  await expect(page).toHaveScreenshot('dashboard-kpi-expanded.png');
});
```

---

## Documentation practices

Documentation is the cross-session memory of a codebase. If it goes stale, future sessions lose the context they need to act correctly.

### Status documents update with work, not later

**Classification:** Pattern. Self-applied. A SessionStart hook warns on stale SCRATCHPAD / backlog, but no hook blocks execution over staleness.

**The rule.** Update `SCRATCHPAD.md`, `docs/backlog.md`, and the active plan's status **immediately** when work completes — before moving to the next task, before closing the session, before anything else. "I'll update docs later" means "docs will be stale."

**Why it exists.** Status documents decay fast. A SCRATCHPAD that says "working on task 3.2" after task 3.2 has been done for three days is worse than no SCRATCHPAD at all — it actively misleads the next session. A backlog entry that says "implement X" when X has already been implemented (but not checked off) wastes cycles; someone will start implementing X again before realizing the work is done.

The failure mode that drives this rule is not laziness — it's optimism. "I'll update SCRATCHPAD at the end of the task" sounds reasonable but compresses poorly under time pressure. The task runs long, the session wraps, the update gets deferred to "next session," and the next session picks up stale context. Updating immediately after each completed unit (not "at the end") is the only reliable path.

**How the harness enforces it.** `adapters/claude-code/CLAUDE.md` Execution section documents the rule. A compact SessionStart hook (as described in Neural Lace's harness architecture) checks SCRATCHPAD and backlog freshness at session start and warns if either's date header is older than today. The warning is a nudge, not a block.

**When to break it.** You don't. The one legitimate pattern is batching: if you complete three small tasks in a tight sequence, one SCRATCHPAD rewrite that captures all three is fine — the key is that the rewrite lands before the next piece of work starts, not that each micro-task produces its own update. Rewrites, not appends, are the preferred pattern (SCRATCHPAD is a pointer, not a log).

### Harness-review skill — weekly full-tree audit

**Classification:** Hybrid. The skill itself is a Pattern (self-invoked weekly or on demand); the checks it runs are Mechanism (scripted audits).

**The rule.** The `/harness-review` skill runs weekly (scheduled) and checks: enforcement-map integrity (every hook/agent/skill referenced in rules files actually exists on disk), dead internal links in docs, rule-reference integrity (a rule cited from another rule must resolve), stale decision records (records with Status unclear or contradicted by current behavior), ungitignored sensitive files (any file under `.claude/local/` or `SCRATCHPAD.md` accidentally committed), and harness-repo drift (files in `~/.claude/` that don't match `neural-lace/adapters/claude-code/`).

**Why it exists.** Harness code rots in subtle ways. A hook gets renamed; rules still reference the old path. A decision gets reversed; the record still claims `Status: Active`. A new sensitive-file pattern gets added to `.gitignore` for new projects but an old project has the file committed from before the pattern existed. None of these are caught by pre-commit checks — they're caught by sweeping the full tree against the current definition of "correct."

A weekly cadence balances cost and drift tolerance. Shorter cadences (per-session) add friction without catching meaningful new drift. Longer cadences (monthly) let drift accumulate past the point where any one finding is easy to triage.

**How the harness enforces it.** `adapters/claude-code/skills/harness-review.md` defines the skill — the checks it runs, the output shape, the remediation expectations. Findings are written to `docs/reviews/YYYY-MM-DD-harness-audit.md` for traceability.

**When to break it.** Running the skill less often than weekly is a judgment call — a stable harness may run it monthly without meaningful drift. Skipping the skill entirely is not advisable; the checks it performs are not duplicated elsewhere.

### Code-to-docs atomicity

**Classification:** Mechanism (pre-commit gate). The "stage docs with code" rule is hook-enforced via `adapters/claude-code/hooks/docs-freshness-gate.sh`.

**The rule.** When a harness-layer file is created, deleted, or renamed, the corresponding documentation entry in `docs/harness-architecture.md` (the file-by-file enforcement map) or `docs/harness-guide.md` must be staged in the same commit.

**Why it exists.** The harness-architecture document is the canonical list of what exists and what each file does. If it drifts from reality — hooks listed that were renamed, agents documented that were deleted — it stops being a reliable reference. Future sessions (AI or human) that consult it to answer "does this exist?" get the wrong answer.

Atomicity in the same commit is the discipline that keeps this from drifting. A rename commit that updates the file but not the doc passes review; six months later a reviewer searches for the old path and finds a reference that doesn't resolve. Forcing both changes into the same commit closes that gap.

**How the harness enforces it.** `adapters/claude-code/hooks/docs-freshness-gate.sh` is a pre-commit hook that detects structural changes (A=Added, D=Deleted, R=Renamed) to files under `adapters/claude-code/{hooks,rules,agents,skills,commands}/` or `principles/` and blocks the commit unless at least one of `docs/harness-architecture.md`, `docs/harness-guide.md`, or `docs/best-practices.md` is also staged. Modifications (M) to existing files do not trigger the gate — only structural changes that affect the documented inventory. See `adapters/claude-code/rules/harness-maintenance.md` for the narrative rule this hook enforces.

**When to break it.** Rarely. If a file's purpose is genuinely too minor to document in `harness-architecture.md` (a one-line helper, a transient template), leaving it undocumented is fine — but then it should not appear in the doc at all. The rule is "if it's documented, keep the doc current," not "document everything."

---

## Autonomy practices

These practices calibrate when the AI should proceed on its own and when it should stop to ask. The underlying principle: autonomy is a gift, not a mandate. The AI earns wider autonomy by being disciplined with narrower autonomy.

### Work autonomously, escalate Tier 3 decisions

**Classification:** Pattern. Self-applied.

**The rule.** Work autonomously with minimal interruptions for reversible work. Stop and escalate for Tier 3 decisions (schema changes, auth changes, public API changes, production-data changes) — do not guess, do not pick one and proceed.

**Why it exists.** Interruptions are expensive for the user, and a well-disciplined AI can handle the majority of work without them. But interruptions are cheap compared to irreversible mistakes. The autonomy-calibration question is always "what is the cost of pausing vs. the cost of being wrong?" For reversible work, cost of pausing > cost of wrong; proceed. For Tier 3 work, cost of wrong >> cost of pausing; escalate.

**How the harness enforces it.** `adapters/claude-code/CLAUDE.md` Autonomy section documents the rule. The tier system in `adapters/claude-code/rules/planning.md` provides the classification framework. No hook detects "you should have escalated here" — this is self-applied discipline.

**When to break it.** You don't break this rule; you calibrate it. Over-escalation (asking about every trivial choice) wastes user attention and signals the AI doesn't understand what's reversible. Under-escalation (proceeding on Tier 3 choices without approval) is the failure mode this rule exists to prevent. The right middle: escalate when a reasonable user would want the chance to choose, proceed when any reasonable choice is acceptable.

### Ambiguous minor details — reasonable choice, state the assumption

**Classification:** Pattern.

**The rule.** When a minor detail is ambiguous (variable naming, test name, log-message wording, ordering of function declarations), make a reasonable choice and state the assumption. Do not stop to ask.

**Why it exists.** Stopping to ask about every minor detail signals the AI can't handle ambiguity, which forces the user to pre-specify things they don't care about. Stating the assumption is the bridge: the AI proceeds, the user sees the assumption in the response and can correct it if it's wrong. The correction cost is low; the blocking cost of pre-asking is high.

**When to break it.** When the "minor" detail turns out to be load-bearing. A variable name that will appear in a public API is not minor. A log-message format that's consumed by a parser is not minor. The test of minor-ness is: "if this choice is wrong, is the fix a one-line rename?" If yes, proceed + state assumption. If no, escalate.

### Multiple valid approaches — pick simplest, note alternatives

**Classification:** Pattern.

**The rule.** When multiple approaches are valid and roughly equivalent in quality, pick the simplest and briefly note the alternatives. Do not open a decision discussion for every choice.

**Why it exists.** Most engineering work has three reasonable approaches and three unreasonable approaches. Discussing the unreasonable ones wastes time; discussing the reasonable ones rarely changes the outcome. The simplest-of-equivalents heuristic defaults to the choice future maintainers will thank you for — simple code is cheaper to read, cheaper to modify, and cheaper to replace.

Briefly noting alternatives (one line, in the plan or commit message) preserves the option to revisit the choice without demanding a full discussion up front. "Chose iterator approach over stream approach; stream would be faster at >10k items but we're bounded at ~100" is enough context for a future reader.

**When to break it.** When the choice is a Tier 2+ decision (has meaningful consequences, affects multiple files, commits to an API shape), it gets the full treatment — alternatives documented, recommendation given, user asked. The "pick simplest" heuristic is for Tier 1 choices where any reasonable option works.

### Bugs outside current task — flag, don't fix unless trivial

**Classification:** Pattern.

**The rule.** When you notice a bug outside the current task's scope, flag it (add to `docs/backlog.md`, mention in the commit message, spawn a task) but do NOT fix it unless the fix is trivial (< 5 minutes).

**Why it exists.** Scope creep is the enemy of completable work. A task that was going to take 30 minutes balloons to 2 hours when "while I was there I also fixed X and Y and Z." The fixes may all be correct, but the original task takes longer, the commit is harder to review, and a future bisect through this commit will touch unrelated changes.

The discipline is: current task gets current-task work. Outside-task observations go to the backlog. The observations don't disappear — they get captured for a future session to address. The current commit stays focused.

The "trivial" exception exists because reasonable boundaries aren't absolute. Fixing an obvious typo, adding a missing import, updating a test fixture that your changes broke — these are within-touched-file cleanups that don't belong in a separate commit. The test: "would splitting this into a second commit add meaningful review value?" If no, it's trivial. If yes, it's a follow-up.

**When to break it.** Bugs that block the current task — literally prevent it from completing — get fixed, because "flag and defer" would leave the current task incomplete. Security bugs discovered in code you're already modifying get fixed immediately regardless of scope, because "flag and defer" risks the bug being re-forgotten and shipping longer.

### After 3 failed attempts — stop and report

**Classification:** Pattern.

**The rule.** After three failed attempts at the same step (same bug, same test, same compile error, same deploy failure), stop and report to the user. Do not continue iterating.

**Why it exists.** The first failure is a symptom. The second failure suggests the first fix didn't address the root cause. The third failure strongly suggests the root-cause diagnosis is wrong and the AI is hill-climbing a local minimum — making changes that look plausible but aren't informed by the actual cause. At that point, continued iteration wastes cycles and often digs the hole deeper (adds changes that have to be reverted later).

Stopping at three doesn't mean giving up. It means escalating with a specific report: what was tried, what happened each time, what hypothesis remains un-eliminated. The user can then redirect (often to the root cause the AI missed) with ten minutes of their attention instead of an hour of iterated misses.

**How the harness enforces it.** `adapters/claude-code/CLAUDE.md` Autonomy section documents the rule. No hook counts attempts; this is self-applied. The diagnosis protocol (see next section) reinforces the principle: "name the root cause before fixing" is upstream of "don't iterate blindly."

**When to break it.** Three is a heuristic, not a law. A problem that's already had four attempts across previous sessions doesn't reset to zero just because a new session started — cumulative attempts count. Conversely, a problem where each "attempt" is genuinely testing a different hypothesis (attempt 1: network config; attempt 2: auth token; attempt 3: endpoint URL — each a different root cause) may warrant attempt 4 if the search space has narrowed meaningfully.

---

## Diagnosis practices

These practices address how to analyze a problem before changing code. The motivating failure: four rounds of "fixes" to a bug that was never correctly diagnosed, each treating a different symptom while the actual root cause (a frozen timestamp) sat untouched.

### Diagnosis before fixing — read the full chain

**Classification:** Pattern. Supported by the `diagnostic-agent`, which the orchestrator invokes first in the bug-fix loop.

**The rule.** Before proposing any fix, read the full stack that influences the symptom. For a UI symptom: form component + API route + backend query + response consumer, read together. Trace a concrete value end-to-end through every layer.

**Why it exists.** "This component renders wrong" is almost never the component's fault. The data it receives is wrong, or the API that produces the data is wrong, or the backend query that feeds the API is wrong. Fixing the component (adjusting a sort, tweaking a filter) treats the symptom at the last layer instead of the cause at an earlier layer.

The full-chain read catches this. Walking a concrete value through each step — what does the form send, what does the API receive, what does the query return, what does the component consume — shows exactly where expected behavior diverges from actual behavior. At that divergence point lives the root cause.

**How the harness enforces it.** `adapters/claude-code/rules/diagnosis.md` documents the process. `adapters/claude-code/agents/diagnostic-agent.md` (referenced in the diagnosis rule) is the structured diagnoser: given a symptom, it produces a diagnosis with root-cause file:line and a predicted fix. The orchestrator invokes it as step 1 of the bug-fix loop.

**When to break it.** Truly isolated bugs — a typo in a string constant, an off-by-one in a local loop — don't need full-chain reads. The rule applies to symptoms whose cause is not obviously local. A good test: "if I changed only this file and the bug persisted, would I be surprised?" If yes, full-chain read. If no, fix locally.

### Exhaustive by default — assume multiple bugs

**Classification:** Pattern.

**The rule.** When a user reports a problem, assume multiple problems until proven otherwise. Trace the entire chain, identify all issues (not just the first one), and fix them all in one diagnosis pass.

**Why it exists.** Bugs travel in packs. A broken deploy usually reflects a broken test config plus a broken env var plus a missing migration, not one of those three. Fixing only the one you noticed first means the user re-reports the failure after your fix and you repeat the cycle with issue #2, then #3. Each round of "fix and re-test" is expensive; one thorough diagnosis followed by one comprehensive fix is far cheaper.

Exhaustive diagnosis changes the question from "what's the bug?" to "what are all the bugs in this chain?" The first version has an answer of "one thing." The second has an answer of N things. N is almost always > 1 when the chain is long enough to be worth walking.

**When to break it.** When the problem is provably local and provably singular — a typo in a string, a single wrong number. Most problems worth diagnosing are not this simple.

### Root cause required before any fix

**Classification:** Pattern. Supported by the fix-verifier agent, which re-traces the concrete value after the fix and rejects symptom-level changes.

**The rule.** Every fix must identify the specific file:line where expected behavior diverges from actual behavior. If you can't name the root cause (which file, which line, what value is wrong, why), you haven't diagnosed the problem yet. Do not start coding.

**Why it exists.** This is the rule the 2026-04-17 failures motivated. Four rounds of "fixes" to a message-ordering bug each treated a downstream effect: a sort was added, a busy guard was added, optimistic rendering was added. None addressed the actual cause — a `simulated_clock` timestamp that stopped advancing after turn 1, so all subsequent messages got the same timestamp and sorted into arbitrary order. The two-line fix (advance the clock) replaced four rounds of symptom treatment.

Naming the root cause forces the diagnosis to be concrete. "Messages are in the wrong order" is a symptom description. "`simulated_clock` reads from `session.simulated_clock` at line 52 of the handler, but that value is never updated after turn 1" is a root cause. Only the second version tells you what line to change.

**How the harness enforces it.** The diagnostic-agent's output contract requires a root-cause file:line. The fix-verifier (`adapters/claude-code/agents/fix-verifier.md`, referenced in diagnosis.md) re-runs the user's workflow after the fix and traces the same concrete value through the fixed code, confirming the divergence is gone at the named line.

**When to break it.** You don't. If you can't name the root cause, the correct action is to keep diagnosing, not to guess at a fix.

### Mandatory diagnostic loop

**Classification:** Pattern.

**The rule.** Every bug fix follows this five-step loop:

1. **Diagnose** — invoke the `diagnostic-agent` with the symptom. It returns a structured diagnosis with root-cause file:line and predicted fix.
2. **Review the diagnosis** — confirm the root cause makes sense. A vague diagnosis or one that names a symptom instead of a cause gets sent back.
3. **Build the fix** — dispatch the builder with the CONFIRMED diagnosis. The fix lands at the diagnosed location, not somewhere else.
4. **Verify the fix** — invoke the `fix-verifier` with the original diagnosis + the builder's commit. It traces the concrete value through the fixed code, runs the user's exact workflow, takes a screenshot, checks for regressions.
5. **Confirm resolution** — fix-verifier returns PASS/FAIL/INCOMPLETE. FAIL means re-diagnose (root cause was wrong). INCOMPLETE means address the gap and re-verify. PASS means the fix ships.

**Why it exists.** Every "obvious" bug the orchestrator tried to skip-step-1 on (as of 2026-04-17, four of four) had a non-obvious root cause. Obvious-looking symptoms had frozen timestamps, invisible dark-mode text, and missing panel headers after component merges. The diagnostic-agent exists specifically to prevent "it's probably X" reasoning, which is wrong more often than it feels wrong.

The loop is five steps because each step addresses a distinct failure mode:
- Step 1 (diagnose) prevents "guess at a fix"
- Step 2 (review) prevents "accept a symptom-level diagnosis"
- Step 3 (build) prevents "fix at the wrong location"
- Step 4 (verify) prevents "the code looks correct ≠ the fix works"
- Step 5 (confirm) prevents "mark done based on builder assertion"

**When to break it.** You don't. The loop has no legitimate shortcuts. Under time pressure the temptation is to skip step 1 for "obvious" bugs, but the base rate of obvious-bugs-with-non-obvious-causes is high enough that skipping step 1 loses more time than it saves.

---

## UX practices

These practices apply to user-facing surfaces. They are the most opinionated section of this document, because UX quality is where harnesses most often under-deliver. A feature that works but confuses, a page with no entry point, an error message that blames the user — these ship regularly when nothing mandates otherwise.

### Errors suggest a solution

**Classification:** Pattern.

**The rule.** Every error message offers a suggested action or resolution. "Failed to save" is banned. "Failed to save — check your connection and try again" is acceptable. "Couldn't save — your session expired. [Sign in again]" is better.

**Why it exists.** An error message that only describes the failure leaves the user stuck. They don't know if the problem is their fault, the system's fault, transient, or permanent. They don't know what to try next. They either give up (silent churn) or ask for help (support cost), both of which are more expensive than writing a useful error message once.

A suggested action converts a dead-end into a next step. Even when the suggestion is imperfect ("check your connection" when the real cause is a server bug), it reduces user confusion and gives the system a path to graceful recovery.

**How the harness enforces it.** `adapters/claude-code/rules/ux-design.md` rule 1 documents the pattern. `audience-content-reviewer` flags error strings without suggested actions during UX validation. The rule is self-applied at authoring time; the agent provides adversarial pass.

**When to break it.** Errors that genuinely cannot suggest an action (a corrupted state the user cannot fix) should still say so explicitly: "This record is corrupted. Contact support with reference #12345." The rule is "offer a solution where one exists," not "fabricate a solution when none does." Silence is never the answer.

### Empty states explain why + offer a first action

**Classification:** Pattern.

**The rule.** Every empty state has three parts: an icon or visual, an explanation of why the state is empty, and a first-action button or link. "No transactions yet. Import a CSV or add one manually. [Import CSV] [Add manually]" — not a bare "No data."

**Why it exists.** Empty states are where first-time users evaluate whether a product is worth their effort. A blank page with "No data" tells the user nothing — they don't know if they set something up wrong, if the feature is working, or what to do next. They leave.

An explanation answers the "why." A first-action button answers the "now what." Together they turn an empty state into an onboarding moment. The same principle applies to empty states users see repeatedly: even a returning user benefits from being reminded of the entry point.

**How the harness enforces it.** `adapters/claude-code/rules/ux-design.md` rule 3. `adapters/claude-code/rules/ux-standards.md` State Handling section lists empty-state requirements. UX agents during validation flag empty states that lack the three elements.

**When to break it.** Empty states in contexts where the user's next action is obvious from context (an inbox with no new messages on a page whose entire purpose is reading messages) can be terser. The rule is about first-time and confused-user cases, not about every possible empty state.

### Destructive actions require confirmation with reversibility info

**Classification:** Pattern.

**The rule.** Every destructive action (delete, archive, remove, disconnect) prompts for confirmation. The confirmation explicitly states what will happen AND whether it is reversible. "Archive? All data preserved, restore anytime from Archived Items." or "Delete permanently? This cannot be undone."

**Why it exists.** Irreversible actions taken by mistake cost the user their data. The cost of a confirmation click (roughly zero) is far below the cost of a mis-click on delete (lost work, lost trust). The reversibility statement is the load-bearing part — "Archive? Yes/No" without the reversibility note is not enough, because the user may not know whether "archive" is reversible in this product.

**How the harness enforces it.** `adapters/claude-code/rules/ux-design.md` rule 4. UX agents check destructive actions during validation.

**When to break it.** Actions that are genuinely not destructive (toggle a filter, switch a tab) don't need confirmations — overuse of confirmations trains users to click through them. The rule is destructive actions, defined as "loses data or access that the user might want back."

### Purple = AI

**Classification:** Pattern. Self-applied; color discipline is the hardest UX rule to mechanically enforce because "purple on a purple-tinted background" slips through color-value matching.

**The rule.** Purple is reserved for AI features. Every AI-generated block, AI-triggered action, AI badge, and AI sparkle (✦) icon uses purple consistently. Non-AI primary actions use blue, not purple.

**Why it exists.** Users need a visual language to quickly parse "this is AI" from "this is the system's normal behavior." Consistent color for AI accomplishes this with one glance. Inconsistent color (purple for some AI things, blue for others, mixed with purple for a non-AI primary button) destroys the signal — users learn that purple means nothing in particular, and the visual language collapses.

The rule is strict specifically because the temptation to use purple for non-AI features is real (purple looks good; it differentiates from blue-heavy UIs), and once it drifts, it's hard to reverse.

**How the harness enforces it.** `adapters/claude-code/rules/ux-standards.md` Color Rules + AI Features sections. The consistency audit script flags some color misuses. UX agents flag AI-feature surfaces that don't use purple and primary actions that incorrectly use purple.

**When to break it.** You don't break this one. The cost of "a little purple on this non-AI button" compounds across the codebase as other contributors see the precedent and copy it. Hold the line.

### Color is never the only signal

**Classification:** Pattern.

**The rule.** Any meaning carried by color must also be carried by a text label, icon, or pattern. A red KPI is paired with "↓" or "declining." A green status dot is paired with "Active" text. A colored category tag is paired with the category name.

**Why it exists.** Accessibility is the headline reason — color-blind users can't distinguish red from green, and dark-mode users may see washed-out versions of both. But the rule applies to all users: color is an ambient signal and gets missed in quick scans. Pairing color with explicit text or icon makes the signal reliable for everyone.

**How the harness enforces it.** `adapters/claude-code/rules/ux-standards.md` Color Rules section. UX agents flag color-only signals during validation.

**When to break it.** Rarely. The exception case is UI where the color is purely decorative (a brand accent on a logo), not carrying meaning. If the color means something, pair it with text.

### Every number needs context

**Classification:** Pattern.

**The rule.** Every KPI or metric displayed shows context: a trend indicator (↑/↓ with %), a comparison ("vs last month"), a tooltip explaining what the metric means and what "good" looks like, or a clickthrough to the underlying data. A bare "247" is not informative.

**Why it exists.** Numbers without context force the user to do their own analysis — is 247 high or low? Is it going up or down? Was last week 250 or 200? Good dashboards answer these questions in-band. Bare numbers shift the analysis cost onto every viewer, every time.

Numbers that represent lists (e.g. "12 unassigned contacts") must be clickable, linking to the list itself. A dead-end number is a UX anti-pattern — the user's most likely next action is "show me those 12 contacts," and denying that action wastes their time.

**How the harness enforces it.** `adapters/claude-code/rules/ux-standards.md` Every Number Needs Context section. UX agents flag context-less numbers during validation.

**When to break it.** Micro-displays where context would overwhelm the value (a counter next to a button, a badge on a nav item) can be bare. The rule is about dashboard-scale numbers, not every integer on the page.

### Every card is clickable

**Classification:** Pattern.

**The rule.** Summary cards on dashboards and index pages are clickable, navigating to the detail view for that card's data. Cards use `cursor-pointer hover:shadow-md` to signal affordance.

**Why it exists.** A dashboard card that shows "12 unassigned contacts" invites the user to see those contacts. If clicking the card does nothing, the user has to find another entry point (a menu item, a sidebar link) to get to the data. That extra navigation step is friction, and the friction compounds across every card on every dashboard page.

Making every card a navigation affordance — even cards whose primary purpose is display — collapses this friction. Users learn "if I want to see the data behind this number, I click the card."

**How the harness enforces it.** `adapters/claude-code/rules/ux-standards.md` Every Card Is Clickable section.

**When to break it.** Cards showing metrics that don't have a list behind them (a system uptime percentage, a global aggregate with no underlying records) can be non-clickable — they're terminal by design. The rule is "if there's a detail view, link to it from the card," not "every card must navigate somewhere."

---

## Commit practices

These practices shape the git history. A clean history is a tool for future debugging, rollback, and understanding — and it's cheap to produce if you commit thoughtfully.

### Commit at natural milestones, not after every small change

**Classification:** Pattern.

**The rule.** Commit when a coherent unit of work is complete, not after every file save. A commit should represent a revertible, reviewable unit — a feature, a bug fix, a refactor step, a test addition.

**Why it exists.** Git history is read far more than it's written. Every `git log` view, every `git blame` lookup, every bisect session consumes the history. A history where every line is its own commit (`fix typo`, `remove space`, `add import`, ... across 40 commits) is impossible to navigate. A history where every commit represents a meaningful unit is navigable in seconds.

The opposite failure — massive "finished week of work" commits — is equally bad for a different reason: they can't be partially reverted. If one change in the commit turned out to be wrong, reverting the commit loses the other nine changes with it. A "natural milestone" is large enough to be reviewable as a coherent unit but small enough to be revertible without collateral damage.

**How the harness enforces it.** `adapters/claude-code/rules/git.md` documents the rule. No hook enforces commit granularity; this is self-applied discipline, with pre-commit review agents catching "this commit does three unrelated things" via scope checks.

**When to break it.** When a change genuinely cannot be sliced into smaller pieces (a rename that touches 200 files, a migration that requires its data-backfill script in the same commit to avoid a broken intermediate state). The rule is the default, not the law; use judgment for special cases.

### Clear `<type>: <description>` commit messages

**Classification:** Pattern.

**The rule.** Commit messages follow `<type>: <description>` where type is one of `feat`, `fix`, `refactor`, `test`, `docs`, `chore`. The description is imperative ("add X", not "added X"), concise (~60 chars), and specific (not "updates" or "fixes").

**Why it exists.** Consistent commit-message structure makes the log scannable. `git log --oneline` is a fast way to see what's been happening; consistent types mean you can filter (`git log --grep '^fix:'`) or just pattern-match at a glance. Imperative tense reads cleanly next to the commit hash: "a4f2b9c feat: add notify-managers button" parses like a sentence. "a4f2b9c added notify-managers button" parses as narrative, which doesn't compose.

The specific-description rule prevents the failure mode of "wip" / "updates" / "stuff" commits, which are essentially noise in the log and make bisect painful.

**How the harness enforces it.** `adapters/claude-code/rules/git.md` documents the style. Pre-commit review catches vague messages; the `commitlint`-style pre-commit hook (project-specific) can enforce the structural format.

**When to break it.** Very rarely. Merge commits on long-running branches may have different shape (`Merge branch 'feature/X' into main`) by necessity. The rule is for authored commits, not for generated ones.

### Never commit directly to main/master

**Classification:** Pattern (aspirational Mechanism — a pre-push branch check could enforce it).

**The rule.** All work happens on feature branches. PRs are the merge path to main/master. Direct commits to main/master are not allowed.

**Why it exists.** Feature branches give you a cheap rollback — if the feature goes wrong, you delete the branch and main is untouched. Direct commits to main force revert-commits or force-pushes to undo, both of which leave traces and are harder to recover from cleanly.

More importantly, PRs force a review gate. Code reviewed before merge catches bugs earlier, surfaces design mistakes before they propagate, and creates an audit trail for why a change was accepted. Committing directly bypasses all of this.

**How the harness enforces it.** `adapters/claude-code/rules/git.md` documents the rule. Repo-level branch protection on main/master (configured in GitHub settings, not in the harness) is the actual mechanical gate. The harness reminds; the repo enforces.

**When to break it.** Single-maintainer repos with no collaborators can commit directly to main for trivial changes (docs, README updates, config tweaks) if the maintainer has deliberately decided the PR overhead isn't worth it for those changes. The rule still applies to any substantive code change.

### Never force-push to protected branches

**Classification:** Mechanism (at the repo level, via branch protection rules) + Pattern (across all remotes).

**The rule.** `git push --force` to main/master or other protected branches is never acceptable without explicit user authorization in the current session. Force-pushing rewrites history and can destroy collaborators' work silently.

**Why it exists.** A force-push rewrites the remote's history. If anyone else has pulled, their local copy now points at commits that no longer exist on the remote. Their next push will be rejected; their next pull will try to merge diverged histories. If they pushed in the meantime, their work is gone from the remote (still on their machine, but invisible to everyone else until they notice).

Even solo-developer force-pushes are dangerous: if you've pushed a branch to a public remote and then force-pushed over it, consumers of that branch (CI, deploy automation, other clones) may all break in ways that are hard to diagnose.

**How the harness enforces it.** `adapters/claude-code/rules/git.md` documents the rule. Repo-level branch protection on the remote is the mechanical enforcement. The global pre-push scanner flags force-pushes to protected branches and requires an explicit user acknowledgment to proceed.

**When to break it.** When the user explicitly says "force-push this branch to main" in the current session (not a previous session, not a general permission) AND the consequences have been explained AND no collaborators are affected. Force-pushing to a personal feature branch that only you are working on is low-risk. Force-pushing to a shared branch is a different matter entirely.

### Never skip hooks without explicit user authorization

**Classification:** Pattern. The hooks themselves are mechanisms; skipping them via `--no-verify` is a pattern failure.

**The rule.** Never use `git commit --no-verify`, `git push --no-verify`, `--no-gpg-sign`, or other hook-bypass flags unless the user explicitly asks for it in the current message. If a hook fails, investigate and fix the underlying issue.

**Why it exists.** Hooks exist because the kinds of checks they perform (credential scanning, test gating, evidence verification) aren't reliably caught elsewhere. Skipping a hook to "just get this commit through" throws away the defense the hook was there to provide. The default failure mode is: the commit lands with a real problem the hook would have caught, and the problem only surfaces downstream.

`--no-verify` is a tool for the developer, not the AI. When a hook fails unexpectedly, the correct path is: read the failure, understand why it fired, either fix the underlying issue (if it's a real problem) or refine the hook (if it's a false positive). Skipping the hook to push the commit is almost never the right answer — and when it is, it's a decision the user should make explicitly.

**How the harness enforces it.** `adapters/claude-code/rules/git.md` documents the rule. The global pre-push scanner cannot itself be skipped via `--no-verify` when wired via `core.hooksPath` for most operations, but pre-commit hooks can. The rule is self-applied when the tooling allows bypass.

**When to break it.** When the user explicitly says "bypass the hook for this commit" in the current message AND the reason is understood (usually: the hook has a false positive that will be fixed in a follow-up commit, and this commit is urgent). Even then, the follow-up commit to fix the hook should land immediately, not "later."

---

## References

- `principles/harness-hygiene.md` — the load-bearing hygiene rule (the "what never ships" catalog)
- `principles/core-values.md` — the underlying values the harness optimizes for
- `adapters/claude-code/rules/planning.md` — decisions, scope, mid-build protocol, completion reports
- `adapters/claude-code/rules/testing.md` — E2E discipline, UX validation, deployment validation, purpose validation
- `adapters/claude-code/rules/vaporware-prevention.md` — anti-vaporware enforcement map (Gen 4)
- `adapters/claude-code/rules/orchestrator-pattern.md` — sub-agent dispatch for long plans
- `adapters/claude-code/rules/diagnosis.md` — full-chain diagnosis, mandatory diagnostic loop, root-cause requirement
- `adapters/claude-code/rules/git.md` — commit style, branch strategy, force-push policy
- `adapters/claude-code/rules/ux-design.md` — error messages, empty states, destructive actions
- `adapters/claude-code/rules/ux-standards.md` — color rules, contrast, state handling, AI features
- `adapters/claude-code/rules/harness-maintenance.md` — global-first rule changes, commit atomicity, sync discipline
- `docs/harness-architecture.md` — detailed enforcement map + per-file purpose
- `docs/harness-guide.md` — file-by-file reference
- `docs/SETUP.md` — two-layer config walkthrough

## Contributing

Propose new best practices by opening an issue. The bar for inclusion has three elements:

1. **Generally applicable.** The practice must apply to more than one project or one team's situation. Project-specific conventions belong in that project's `CLAUDE.md`, not here.
2. **Enforceable or checkable.** A practice that can only be described ("write clean code") but not checked is aspirational, not actionable. Either a hook can gate it, an agent can review it, or a checklist can verify it — something must make the practice real.
3. **Worth the friction.** Every rule adds friction. The practice must solve a problem expensive enough that the friction is net-positive. Rules that solve imaginary or rare problems accrete over time into bureaucracy.

When proposing a practice, include:

- The rule (one sentence)
- Why it exists (the motivating problem, with a concrete example)
- How it would be enforced (hook, agent, script, or self-applied Pattern with justification for why mechanical enforcement isn't feasible)
- When to break it (the honest edge cases)

Practices that fail any of the three criteria are rejected. Practices that pass are added to this document with a reference to the enforcing mechanism or documented pattern.
