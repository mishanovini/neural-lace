#!/bin/bash
# scope-enforcement-gate.sh — Phase 1d-C-1 (C10), 2026-05-04 second-pass redesign
#
# PreToolUse hook that blocks `git commit` when staged files fall outside
# the active plan's declared scope.
#
# Rule (mechanism): every commit on a plan-governed feature branch must
# stage only files declared in scope. Out-of-scope commits silently expand
# work beyond the plan; this hook surfaces them at commit time and forces
# either a scope amendment, a new plan to claim the work, or a deferral.
#
# Trigger:
#   PreToolUse on tool_name == "Bash" OR "PowerShell" (settings matcher
#   "Bash|PowerShell" — HARNESS-GAP-47, 2026-06-10, closed the PowerShell
#   bypass: the PowerShell tool runs `git commit` just like Bash and is
#   parsed with the same command patterns; `cd` is a Set-Location alias and
#   `Set-Location` itself is recognized). Splits the command on `&&` / `;`,
#   tracks `cd` / `Set-Location` targets, matches `git commit` (including
#   `git -C <path> commit`) as a segment. Pass-through on other tools and
#   non-commit commands.
#
# Target-repo resolution (HARNESS-GAP-47, 2026-06-10):
#   The gate evaluates ALL its logic (plan discovery + staged-file listing)
#   against the repo the commit actually TARGETS, not the hook process's own
#   cwd (the session root). Pre-fix, `cd <other-repo> && git commit` was
#   evaluated against the SESSION repo's docs/plans + staged index, and
#   `git -C <other-repo> commit` bypassed the gate entirely (the old
#   `^git\s+commit` regex never matched it). Effective-target priority:
#     1. `git -C <path>` flags on the commit segment — quoted paths with
#        spaces supported, repeated -C composes per git semantics (later
#        relative paths resolve against earlier ones), glued -C<path> too.
#     2. The last `cd <path>` / `Set-Location <path>` segment preceding the
#        git-commit segment (`&&` and `;` chains, quoted paths, ~ expansion,
#        chained relative cds accumulate).
#     3. Fallback: process cwd (the pre-GAP-47 behavior, unchanged).
#   A parsed target that doesn't exist or isn't a git repo passes through
#   with a stderr note — the real git command will fail on its own; there is
#   nothing meaningful to scope-check. Self-test scenarios 26-31 cover this
#   plus the PowerShell tool coverage.
#
# No-docs/plans/ full-skip (2026-06-08):
#   A repo with NO docs/plans/ directory cannot have plan-scoped commits —
#   there is nothing to scope against — so the gate skips the check entirely
#   and allows the commit (with a brief stderr note). This is the correct
#   general fix; it unblocks committing operational state to repos that don't
#   use the plan workflow (e.g. the workstreams-coordination state repo).
#   Self-test scenario 25 covers it.
#
# System-managed-path allowlist (2026-05-04):
#   `docs/plans/archive/*` and `docs/plans/archive/*-evidence.md` are
#   exempt — these files are moved by `plan-lifecycle.sh` on Status:
#   COMPLETED/DEFERRED/ABANDONED/SUPERSEDED transitions, not by builder
#   plan work. If ALL staged files are system-managed, allow the commit
#   unconditionally with a brief stderr note. If a mix, do the normal
#   scope-check on the non-system files only.
#
# Rebase / merge full-skip (HARNESS-GAP-29, 2026-05-27):
#   A `git commit` created WHILE a rebase or merge is in progress stages
#   files that git's replay/merge brought in — e.g. origin/master's files
#   applied to a PR branch during conflict resolution — NOT files the
#   author chose per the plan. Scope-checking author-uncontrolled files is
#   meaningless and produces false blocks on the routine "rebase/merge
#   master into a PR branch" operation. So when a rebase- or
#   merge-in-progress is detected, the ENTIRE scope check is skipped and
#   the exemption is logged to `~/.claude/state/scope-gate-exemptions.log`
#   (commit context + reason) for audit.
#
#   Detection (any sufficient):
#     - rebase:  `$GIT_DIR/rebase-apply` or `$GIT_DIR/rebase-merge` exists
#     - merge:   `$GIT_DIR/MERGE_HEAD` exists, OR the `git commit -m`
#                message begins with "Merge branch" (a true merge commit
#                where MERGE_HEAD may already be absent).
#
#   This SUPERSEDES the narrower HARNESS-GAP-27 behavior (which exempted
#   only commit-numbered migration paths during a merge and still
#   scope-checked everything else). That was insufficient: a master
#   merge/rebase stages app code, configs, and docs too, not just
#   migrations. The migration-path allowlist below (`_is_system_managed_path`
#   under IN_MERGE) is retained as documented defense-in-depth but is
#   subsumed by the earlier full-skip whenever MERGE_HEAD is present.
#   Companion "union of plans active on either side" approach is tracked
#   as a separate ADR (see backlog HARNESS-GAP-27).
#
# Active-plan discovery:
#   Iterates docs/plans/*.md (top-level only — excludes archive/). For
#   each, reads first ~50 lines for `Status: ACTIVE`. If no active plan,
#   pass through (gate doesn't apply when no plan governs the work).
#
# Files-to-modify parsing:
#   Locates `## Files to Modify/Create` heading in each active plan,
#   reads until next `## ` heading or EOF. Extracts file paths from
#   bullet lines (`- ` or `* `). Supports backticked paths (`- \`path\` —
#   description`) and plain paths. ALSO parses the optional
#   `## In-flight scope updates` section (format:
#   `- <YYYY-MM-DD>: <path> — <reason>`); a file matching either
#   section is in-scope. Backward compatible — plans without the
#   in-flight section continue to work as before.
#
# Diff comparison:
#   `git diff --cached --name-only --diff-filter=ACMRD` for staged files.
#   For each, check exact match, glob match (`**`, `*`, `?`), or
#   directory-prefix match (bullet ending in `/`).
#
# Multiple active plans:
#   UNION OF THE PLANS' SCOPES. A staged file is IN scope if AT LEAST ONE
#   active plan declares it; it is out of scope only when EVERY active plan
#   rejects it. The error message names which plan rejected which file, and
#   separately names any plan that could not judge the file because its own
#   scope section failed to parse.
#
#   This header used to claim the opposite ("required behavior is
#   intersection — a file in scope of plan A but not plan B is out of
#   scope"), which the code has never implemented. Corrected 2026-07-30
#   (SCOPE-GATE-HEADER-CLAIMS-INTERSECTION-IMPLEMENTS-UNION-01) in favour of
#   the CODE, because intersection is the wrong semantics for this gate:
#
#   1. Plans are independent concurrent workstreams, not conjunctive
#      constraints. This repo routinely carries ~20 ACTIVE plans at once.
#      Under intersection a file would have to be declared by ALL of them to
#      be committable, so essentially every commit would block. Intersection
#      is not merely stricter than union — at N>1 plans it is degenerate.
#   2. It would falsify the gate's own remedy. Option 2 of the block message
#      tells the operator to OPEN A NEW PLAN listing the staged files and
#      re-commit. Under intersection that provably cannot work: the new plan
#      claims the file, but the other active plans still do not, so the file
#      stays out of scope and the commit blocks again. Handing the operator a
#      remedy that cannot be completed is exactly the defect recorded for the
#      review-record remedy chain in _is_system_managed_path above.
#   3. Union is the pre-existing tested oracle. Self-test scenario 12
#      ("new plan staged alongside out-of-scope file claims it") asserts a
#      file is in scope iff at least one active plan claims it, and has
#      passed since the gate was written.
#
#   Scope discipline is preserved because the union is over DECLARED scopes:
#   every in-scope file is still named by some plan, so no commit escapes
#   plan governance. Union picks WHICH plan governs it; it never lets an
#   undeclared file through.
#
# Waivers:
#   REMOVED 2026-05-04. The block-message no longer offers a waiver
#   path. Three structural options (update plan / open new plan / defer)
#   cover every legitimate case. There is no bypass flag: this hook is a
#   PreToolUse gate that pattern-matches the `git commit` command string
#   BEFORE git runs, so `--no-verify` (a git pre-commit-hook bypass) has
#   no effect on it — the block message names the real remediations
#   instead (NL-FINDING-032).
#
# Exit codes:
#   0 — commit allowed (or non-applicable)
#   2 — commit blocked (stderr explains why; JSON {decision: block} on stdout)

# NOTE: `set -u` is intentionally NOT enabled. Bash 3.2 throws "unbound
# variable" on `"${arr[@]}"` for an EMPTY indexed array even when it was
# explicitly declared (a known 3.2 quirk, verified on 3.2.57 — bash 5.3
# does not). The hook handles its own undefined states explicitly.
#
# PORTABILITY (bash 3.2 floor, 2026-07-29): this file MUST run correctly
# under macOS's stock /bin/bash 3.2.57. It previously used `declare -A`
# for FINAL_OOS; under 3.2 that is a hard parse-time error
# ("declare: -A: invalid option"), after which `FINAL_OOS["$sf"]=...`
# was interpreted as an ARITHMETIC subscript on a plain variable, so the
# gate fell straight through to `exit 0` — i.e. it AUTHORIZED every
# out-of-scope commit while appearing to run. There is no environmental
# precondition here on purpose: a git hook, a scheduled task or a cloud
# session may not inherit a PATH with Homebrew's bash 5.x first, and a
# blocking gate must not depend on one. See docs/plans/
# macos-portability-2026-07.md.


# ============================================================
# THIN DISPATCHER (Gate Philosophy Law retrofit, R3.4, harness-execution-
# redesign-2026-08 Task 2). Full mechanism — helpers, --self-test, main
# hook logic, the single block-message decision site — lives in
# scope-enforcement-gate-body.sh, SOURCED only when the command could
# possibly be a `git commit`. This file owns exactly: --self-test/--check
# dispatch, and the cheap pure-bash substring pre-filter so the
# overwhelmingly common case (a Bash/PowerShell command with no "commit"
# substring at all) exits WITHOUT ever sourcing/parsing the ~2400-line body,
# without a single jq spawn.
# ============================================================

# Path resolution is DEFERRED past this point on purpose: `dirname`/
# `basename` are external binaries (a fork each on this platform — the
# exact per-spawn tax this split exists to avoid), and `${BASH_SOURCE[0]}`
# itself is only needed once we know we're actually sourcing the body. The
# overwhelmingly common fast-pass path below (no "commit" substring) computes
# NONE of this — see the resolution site just above each `source` call.
_SEG_ARGV1="${1:-}"

case "$_SEG_ARGV1" in
  --self-test|--check)
    # Parameter-expansion path split (no dirname/basename fork) — see
    # docs/lessons/2026-07-13-...-process-spawn-and-hook-latency.md.
    _SEG_ENTRY_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
    _SEG_ENTRY_PATH="$_SEG_ENTRY_DIR/${BASH_SOURCE[0]##*/}"
    # shellcheck source=scope-enforcement-gate-body.sh
    source "$_SEG_ENTRY_DIR/scope-enforcement-gate-body.sh"
    exit $?
    ;;
esac

# --- Cheap pre-filter (perf; behavior-preserving) ---------------------------
# This gate only ever ACTS on a `git commit` command; every other command is
# a guaranteed pass. A real `git commit` segment contains the literal
# substring "commit" in the raw payload. Pure-bash substring guard — no
# jq/sed/grep spawn, and (the point of this split) the body file is never
# even sourced/parsed on this path. ACCEPTED RESIDUAL (unchanged from the
# pre-split gate, pinned by the body's own obfuscation-boundary self-test
# scenario): a quote/escape-obfuscated form (e.g. `git co""mmit`) has no
# "commit" substring in the RAW payload and skips this pre-filter, while the
# tokenizer inside the body would reconstruct and act on it — deliberately
# scoped to the threat model (accidental scope violations, not adversarial
# obfuscation). Consume the input ONCE (env var else stdin) and re-export it
# so the body's own read is unaffected.
# Ref: docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md rec 5.
_SEG_PF="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$_SEG_PF" ]] && [[ ! -t 0 ]]; then
  _SEG_PF=$(cat 2>/dev/null || echo "")
fi
export CLAUDE_TOOL_INPUT="$_SEG_PF"
case "$_SEG_PF" in
  *commit*) : ;;                 # possible git commit — source the body
  *)                             # no "commit" substring — cannot be a git commit
    [[ "${SCOPE_PRINT_TARGET:-0}" == "1" ]] && printf '0|\n'
    exit 0 ;;                    # <-- the fast-pass exit: zero path-resolution forks paid
esac

_SEG_ENTRY_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
# shellcheck source=scope-enforcement-gate-body.sh
source "$_SEG_ENTRY_DIR/scope-enforcement-gate-body.sh"
exit $?
