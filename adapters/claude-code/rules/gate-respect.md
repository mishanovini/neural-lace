# Gate-respect — Diagnose, Don't Bypass

**Classification:** Pattern (self-applied discipline). No hook detects "you tried to bypass a gate instead of diagnosing it" — the rule lives in the agent's behavior. Sibling Mechanism layers exist for the most-tempting bypass surfaces (force-push, `--no-verify` on most pre-commit hooks, destructive git ops), but `--no-verify` itself remains a usable command and `OVERRIDE=`-style escape hatches in some hooks are still single-line invocations. This rule is what holds the line where Mechanism cannot.

**Originating incident:** PR #197 (2026-05-14). A merge of master into a feature branch produced two scope-enforcement-gate fires across two attempts — once on a Supabase migration pulled in from master, once on a harness-config subtree from a deploy-mode commit. Earlier sessions in the same project repeatedly called the gate "too strict" and asked for `--no-verify` authorization. The actual root cause: my merge-resolution plan was incomplete — it failed to claim `supabase/**` (and later, a harness-config subtree) in its `## Files to Modify/Create` section, so the gate correctly flagged them as out-of-scope. The proper fix was a 2-line plan edit (add the missing path bullets); the gate accepted on the next attempt. No override needed. Several hours of friction across sessions traced back to the agent reaching for the bypass before reading the gate's stderr carefully.

## The rule in one sentence

**When a gate, hook, classifier, or other automated check blocks an action, the FIRST move is always to diagnose why it fired; the SECOND move is to apply the fix the gate's diagnostic suggests; the LAST resort is bypass — and only with explicit per-occurrence user authorization in the current chat.**

## The three-step protocol

### Step 1 — Diagnose

The gate's stderr is the primary diagnostic source. Read it carefully BEFORE doing anything else.

Every Neural Lace gate that blocks an action emits structured stderr explaining (a) what fired, (b) why this specific action triggered it, and (c) the remediation paths the gate accepts. The remediation paths are the gate's contract: "I will allow this action when X, Y, or Z is true." Your job is to make ONE of those true.

Things the stderr typically names:
- The specific file, line, field, or staged path that triggered the block
- The contract the gate enforces (the rule's name + a one-line statement of what the gate is looking for)
- Two-to-four structural remediation options keyed to the trigger, in priority order
- An emergency-override clause (last resort, not first option)

If the stderr is not enough to diagnose, the SECOND move is to read the hook's source — `~/.claude/hooks/<gate-name>.sh` or `adapters/claude-code/hooks/<gate-name>.sh`. The hooks are bash scripts; they are readable in 2-5 minutes. Reading the hook reveals exactly which condition triggered the block for this specific action.

Things to NOT do at Step 1:
- Reach for the override flag because the gate "feels strict."
- Re-run the same action hoping it works (gates are deterministic; identical input produces identical output).
- Assume the gate is buggy until you have actually read both stderr AND the hook source.
- Narrate "the gate is blocking me" without naming the specific trigger and remediation path.

### Step 2 — Apply the proper fix

The gate's stderr names remediation paths. Apply the one whose situation matches yours. For `scope-enforcement-gate.sh` blocking a commit, the three structural options are: UPDATE THE PLAN (the file is in-scope but wasn't pre-listed), OPEN A NEW PLAN (the file is genuinely separate work), or DEFER (the file shouldn't ship at all right now). Pick the one that matches; apply the edit it names; re-run the action.

The fix should make the action satisfy the gate's contract — not bypass the contract. A plan-edit that adds the missing path is the contract being satisfied; a `--no-verify` is the contract being bypassed.

Generalized version of the same pattern, across the harness:
- `prd-validity-gate.sh` blocks plan creation because `prd-ref:` resolves to a missing or shallow PRD. Fix: author or extend the PRD; do NOT add `prd-ref: n/a — harness-development` to a plan that obviously addresses a downstream product feature.
- `pre-commit-tdd-gate.sh` blocks a commit because a new runtime file lacks tests. Fix: write the test; do NOT add the path to a "tests-not-required" allowlist without first proving the file is genuinely test-exempt.
- `plan-edit-validator.sh` blocks a checkbox flip because no fresh evidence block exists. Fix: invoke task-verifier (the only entity that should be flipping checkboxes); do NOT edit the plan to skip the checkbox flip.
- `wire-check-gate.sh` blocks a runtime task's checkbox flip because the declared code chain has a broken arrow. Fix: update the plan's `**Wire checks:**` block to match the actual code, OR fix the code so the declared chain holds; do NOT remove the arrow to make the check pass.
- `findings-ledger-schema-gate.sh` blocks a commit because a `docs/findings.md` entry lacks a required field. Fix: add the field; do NOT delete the entry to dodge the schema.

The general shape of the fix: read the gate's contract, identify the gap between the action and the contract, close the gap.

### Step 3 — Bypass only as last resort, with explicit user authorization

Bypass mechanisms exist (`git commit --no-verify`, `OVERRIDE=...` env vars, override authorization markers, hooks whose stderr names an explicit per-occurrence escape hatch). These are the LAST resort, not the first option. The criteria for bypass:

1. **Clear evidence the gate is a false positive for THIS specific case.** Not "the gate is too strict in general" — the gate's contract is intentional, recurring true-positives don't justify bypass. The evidence has to be specific: "the gate's regex matched X but X is actually Y because of Z." If you cannot articulate the false-positive claim in one sentence with concrete file:line evidence, you don't have evidence; you have friction.

2. **Explicit user authorization in the CURRENT chat — not inference.** The user must have said, in their most-recent message, something like "go ahead and bypass it" or "use --no-verify on this one." General prior permission ("you can decide when to bypass"), inference from context ("the user trusts me"), or a standing rule ("bypass is OK for harness-dev") does NOT satisfy this requirement. A previous session's bypass does not authorize the current session's bypass.

3. **The bypass is logged in the commit message or the session-end summary** so the audit trail is intact.

Asking the user for bypass authorization is itself a signal that you should pause. Many bypass requests dissolve when the agent re-reads the stderr; if the user grants the bypass and then on inspection it turns out the gate was correct, the bypass is the wrong outcome regardless of authorization. The first move is always diagnose, even when the bypass would technically be allowed.

## What this rule is NOT

- **Not a ban on bypass mechanisms existing.** `--no-verify`, override flags, and waiver markers exist for legitimate edge cases — gates need escape hatches for true false positives, just as fire alarms need silence buttons. The rule is about default behavior, not about deleting the safety hatches.
- **Not an instruction to never ask for help.** When the gate's stderr is unclear, or the hook's source is unreadable, or the contract is ambiguous, asking the user for clarification is the right move. The wrong move is asking the user for *permission to bypass* without having diagnosed.
- **Not an exemption for "small" cases.** "It's just one file" / "it's just a typo" / "it's just an edge case" is the most-common rationalization for treating the gate as friction rather than signal. Small cases compound: a session that gets in the habit of bypassing on small cases will reach for bypass on every case.

## When the gate is structurally wrong

Occasionally a gate's contract is genuinely too strict for legitimate work — true false-positives recur across multiple sessions, multiple operators, multiple repos. When that happens, the proper response is **fix the gate**, not bypass-per-occurrence. The recurrence is the signal that the gate needs an extension or a smarter check.

The path:

1. **Open a HARNESS-GAP-N entry** in `docs/backlog.md` (or the equivalent in the project) describing the recurring false-positive pattern, with two or three concrete example sessions.
2. **Propose a remediation** in the entry — a smarter regex, a context-aware allowlist, an additional remediation path in the stderr message, or a sibling Mechanism that handles the recurring case.
3. **Treat the per-occurrence bypass as the workaround until the fix lands.** Document the workaround in the same backlog entry so future sessions hitting the same recurrence don't re-derive it.
4. **Ship the gate fix** as a normal harness-development plan. Test it via the gate's `--self-test`. Sync to the live mirror per the install convention.

Worked example: HARNESS-GAP-27 (2026-05-14) tracks the `scope-enforcement-gate.sh` blind-spot on merge commits. The gate iterates currently-ACTIVE plans, but a merge of master pulls in files from plans that were ACTIVE on master and have since archived. The lightweight fix is to extend the gate's `_is_system_managed_path()` allowlist with migration-class paths when `$GIT_DIR/MERGE_HEAD` exists; the more-general fix (check against UNION of plans active on either side of the merge) needs an ADR. Both paths are documented in the entry. The bypass-per-occurrence workaround is documented too, but the goal is to make it unnecessary.

## Worked example — PR #197

A representative session of the failure mode, anonymized to keep the lesson general.

**What I encountered.** Merge of `master` into my feature branch. `git commit` on the merge produced:

```
SCOPE ENFORCEMENT GATE — COMMIT BLOCKED
...
Out-of-scope staged files:
  • supabase/migrations/20260514120000_add_index.sql
    Rejected by plan(s): merge-resolution-plan
...
```

**What I almost did.** Ask the user for `--no-verify` authorization. "The gate is too strict for merge commits; this migration came from master, not from my feature work."

**What the actual diagnosis revealed.** The gate's stderr named the specific file (`supabase/migrations/20260514120000_add_index.sql`) and the rejecting plan (`merge-resolution-plan`). Reading my own merge-resolution plan, the `## Files to Modify/Create` section did NOT list `supabase/**`. The gate was correctly flagging the migration as out-of-scope per the plan I had authored. My plan was incomplete, not the gate's contract.

**The proper fix.** A 2-line plan edit adding the bullet `- supabase/migrations/*.sql — pulled in from master via merge` to the plan's `## In-flight scope updates` section. Re-staged the plan + the migration. Re-ran `git commit`. Gate accepted.

**The hours-of-friction part.** Before I got to that fix, I burned time exploring the bypass route — checking which override marker the gate accepted, calculating which `--no-verify` invocations the harness's git-discipline rule allows, framing the request to the user. All of that was wasted; the gate's stderr already named the remediation in two-to-four words on a single line.

**The class lesson.** Gates are not friction. Gates are an automated catalog of contracts the work is supposed to satisfy. When a gate fires, the contract has been violated — diagnosing the violation is faster than orchestrating a bypass, and produces a correct outcome instead of a bypassed one.

## Cross-references

- `~/.claude/rules/diagnosis.md` — the broader exhaustive-diagnosis discipline this rule operationalizes for the specific case of "an automated check is blocking me."
- `~/.claude/rules/git-discipline.md` — sibling rule covering force-push prohibition (Rule 1), post-merge sync (Rule 2), and Stop-hook waivers vs retry-guard (Rule 3). Composes with this rule: this rule is "diagnose before bypass" at the per-gate level; git-discipline is "no force-push, no `--no-verify` shortcuts, no retry-loop absorption" at the per-tool level.
- `~/.claude/rules/vaporware-prevention.md` — the enforcement-map naming every gate this rule applies to.
- Memory: `feedback_loud_is_not_rare.md` — the user's principle that audit-logged escape hatches are no harder to use than `--force` for an LLM. This rule is the present-moment friction the memory's principle calls for: agent friction must be diagnosis-discipline, not consequence-deferred ceremony.
- `docs/failure-modes.md` — class FM-N for "bypassed gate when diagnosis would have worked" if/when this becomes a catalogued failure pattern.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | The three-step protocol: diagnose, apply proper fix, bypass-as-last-resort | `adapters/claude-code/rules/gate-respect.md` |
| Sibling gate (Mechanism) | Force-push prohibition (one specific bypass surface) | per `~/.claude/rules/git-discipline.md` Rule 1 |
| Sibling gate (Mechanism) | Stop-hook retry-guard caps loops at 3 retries; this rule says use waivers BEFORE the threshold | `~/.claude/hooks/lib/stop-hook-retry-guard.sh` |
| User authority | The user retains interrupt authority when they see a bypass attempt that lacked diagnosis | (Pattern) |

The rule is documentation-enforced. The most-tempting bypass surface (force-push) is Mechanism-blocked elsewhere. Everything else relies on the agent's self-applied discipline plus the user's interrupt authority.

## Scope

This rule applies in every project whose Claude Code installation has this rule file present at `~/.claude/rules/gate-respect.md`. The rule is loaded contextually by Claude Code's harness; no opt-in or hook wiring is required to make the rule active. The protocol applies to every gate in the harness — Neural Lace's own hooks, project-level hooks downstream of NL, and third-party pre-commit / pre-push / lint / typecheck integrations.
