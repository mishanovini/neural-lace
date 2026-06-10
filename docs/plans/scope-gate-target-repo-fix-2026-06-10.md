# Plan: scope-enforcement-gate — evaluate the commit's TARGET repo + close the PowerShell bypass (HARNESS-GAP-47)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal gate fix; self-test is the acceptance artifact
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal

Fix HARNESS-GAP-47 (7+ live repros 2026-06-09/10, incl. every cross-repo builder commit
in the current program; discovery: `docs/discoveries/2026-06-09-scope-gate-uses-session-cwd-not-cd-target.md`,
filed in backlog v54 — both currently live in the operator's main-checkout session state,
not yet on master). Two proven defects in `adapters/claude-code/hooks/scope-enforcement-gate.sh`:

- **(A) Wrong-repo evaluation.** The PreToolUse hook resolves the repo from its OWN
  process cwd (the session root). A command like `git -C <other-repo> commit …` or
  `cd <other-repo> && git commit …` is evaluated against the SESSION repo's
  `docs/plans/` + staged index (including other sessions' staged files). Worse,
  `git -C <path> commit` did not even match the commit-detection regex
  (`^git\s+commit`), so that form bypassed the gate entirely.
- **(B) PowerShell bypass.** The settings matcher gates only the `Bash` tool; the
  `PowerShell` tool runs `git commit` unexamined.

## User-facing Outcome

The maintainer's gate fires against the repo a commit actually targets: a cross-repo
`git -C <repo> commit` from any session is scope-checked against THAT repo's plans and
staged files (full-skip when the target has no `docs/plans/`, block when the target's
active plan rejects a staged file), and the same enforcement applies whether the command
runs through the Bash tool or the PowerShell tool. Demonstrated by the hook's extended
`--self-test` (the harness's user-facing outcome per the build-harness-infrastructure
work-shape).

## Scope

- IN: target-repo parsing (`git -C`, repeated/glued `-C`, quoted paths with spaces,
  `cd`/`Set-Location` chains with `&&`/`;`, `~` expansion) in
  `adapters/claude-code/hooks/scope-enforcement-gate.sh`; PowerShell tool acceptance in
  the same hook; matcher extension `Bash` → `Bash|PowerShell` for this hook's entry in
  `adapters/claude-code/settings.json.template`; six new self-test scenarios (26–31);
  surgical live-sync of both changes to `~/.claude/` per two-layer config.
- OUT: any other hook with the same cwd-resolution defect class (sibling sweep is a
  follow-up — see Decisions Log); the backlog v54 entry + discovery doc themselves
  (uncommitted operator session state in the main checkout — not this worktree's files);
  PowerShell-specific syntax beyond `cd`/`Set-Location` + `;` chains (e.g. script-block
  `{ git commit }` forms — same residual class the Bash parser already accepts).

## Tasks

- [ ] 1. Defect A: parse the effective commit-target from the command string (priority:
  `git -C` flags on the commit segment → last `cd`/`Set-Location` segment before it →
  process cwd) and run ALL gate logic (plan discovery + staged-file listing) against the
  parsed target's repo root — Verification: mechanical
- [ ] 2. Defect B: accept tool_name `PowerShell` in the hook and extend the
  scope-enforcement-gate matcher in `settings.json.template` to `Bash|PowerShell`;
  note PowerShell coverage in the hook header — Verification: mechanical
- [ ] 3. Extend `--self-test` with scenarios 26–31 (git -C to no-plans repo full-skips;
  git -C quoted-path-with-spaces to plan-repo blocks; cd && commit follows cd target;
  plain commit fallback unchanged; repeated -C composes; PowerShell tool gated) and run
  the full suite green — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/hooks/scope-enforcement-gate.sh` — target-repo parsing, PowerShell tool acceptance, self-test scenarios 26–31
- `adapters/claude-code/settings.json.template` — scope-enforcement-gate matcher `Bash` → `Bash|PowerShell`
- `docs/plans/scope-gate-target-repo-fix-2026-06-10.md` — this plan
- `docs/plans/scope-gate-target-repo-fix-2026-06-10-evidence/` — write-evidence.sh structured artifacts per task

## In-flight scope updates
(no in-flight changes yet)

## Assumptions

- The PowerShell PreToolUse event delivers the same `{tool_name, tool_input.command}`
  JSON shape as Bash (the hook reads `.tool_input.command // .command`).
- The hook process's cwd equals the session cwd, so RELATIVE `cd`/`-C` paths resolve
  identically in the hook and in the actual command.
- `git -C <dir> rev-parse --show-toplevel` is the authoritative repo-root resolution for
  a parsed target; a target that doesn't exist or isn't a repo means the real command
  fails on its own, so pass-through errs toward allow.
- Claude Code PreToolUse matchers are regexes, so `Bash|PowerShell` mirrors the existing
  `Edit|Write` / `Task|Agent` convention in the same template.

## Edge Cases

- Repeated `-C` composes per git semantics (later relative paths resolve against earlier
  ones); glued `-C<path>` accepted; quoted paths with spaces tokenized correctly.
- Chained relative `cd` segments accumulate (`cd a && cd b` → `a/b`); bare `cd` → `$HOME`;
  `~`/`~/x` expand to `$HOME`.
- `git -C sub commit` after `cd /other` resolves `sub` against `/other` (the cd target is
  the base for a relative `-C`).
- Parsed target missing or not a git repo → pass through with stderr note (the real git
  command fails on its own; nothing meaningful to scope-check).
- `commit-tree` / `commit-graph` still excluded (token equality on `commit`).
- Commands with no `-C`/`cd` keep the exact pre-fix behavior (process-cwd evaluation),
  preserving all 25 existing self-test scenarios.

## Acceptance Scenarios
- n/a — acceptance-exempt harness-internal work; the hook's `--self-test` (31 scenarios) is the acceptance artifact.

## Out-of-scope scenarios
- n/a

## Testing Strategy

- Extend the hook's `--self-test` from 25 to 31 scenarios; all 25 existing scenarios must
  stay green (regression) and the 6 new ones cover both defects (A via 26–30, B via 31).
- Evidence per task via `write-evidence.sh capture` with `command:` checks invoking the
  self-test.
- Live-sync verification: `diff -q` hook vs `~/.claude/hooks/` (byte-identical); jq-applied
  matcher edit on live `~/.claude/settings.json` shown as a diff.

## Walking Skeleton
- n/a — single-mechanism fix inside an existing hook; the self-test IS the end-to-end slice.

## Decisions Log

### Decision: parse-the-command-string rather than wrap git
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** parse `git -C` / `cd` / `Set-Location` from the command text in the hook
  (priority -C → cd → cwd), resolve via `git -C <target> rev-parse --show-toplevel`.
- **Alternatives:** (a) a git wrapper shim that exports the target cwd — too invasive,
  touches every git invocation; (b) requiring builders to never use `git -C` — fights the
  documented cross-repo worktree protocol in `orchestrator-pattern.md`.
- **Reasoning:** the hook already receives the full command string; parsing it is local,
  testable, and preserves the pass-through posture for everything else.
- **To reverse:** revert the single hook + template commit.

### Decision: sibling-class sweep deferred
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** fix scope-enforcement-gate only in this plan; other PreToolUse Bash hooks
  that resolve repo state from process cwd (e.g. observed-errors-gate,
  definition-on-first-use-gate, findings-ledger-schema-gate) are the same defect CLASS
  but live behind different trigger semantics; sweeping them needs its own verification
  pass. The class is named here so the follow-up is discoverable (FM/class:
  hook-resolves-cwd-not-command-target).
- **To reverse:** n/a — additive follow-up.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — single-mechanism plan; behavior changes are cited in Tasks + Files entries directly
- S2 (Existing-Code-Claim Verification): swept — commit-detection regex at hook lines 962-983 and cwd-based `git rev-parse --show-toplevel` at lines 985-1006 verified against the file at plan-authoring time
- S3 (Cross-Section Consistency): swept — Edge Cases and Tasks agree on parse priority (-C → cd → cwd)
- S4 (Numeric-Parameter Sweep): swept for params [scenario count 31, existing 25] — consistent
- S5 (Scope-vs-Analysis Check): swept — all Add/Modify verbs target the two claimed adapter files

## Definition of Done
- [ ] All tasks checked off
- [ ] Full `--self-test` green (31/31)
- [ ] Live mirror synced (hook byte-identical; live settings matcher patched)
- [ ] Completion report appended to this plan file
