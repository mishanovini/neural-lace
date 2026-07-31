#!/bin/bash
# review-record-commit-gate.sh — ADVISORY early feedback on an unreviewed
# harness change at commit time. Demoted from BLOCKING to ADVISORY 2026-07-30
# (see "THE 2026-07-30 DEMOTION" below) — hooks/review-record-push-gate.sh
# (pre-push) is now the AUTHORITATIVE carrier.
#
# ============================================================================
# THE 2026-07-30 DEMOTION (read this FIRST — it supersedes "BLOCKS" below)
# ============================================================================
# This gate blocked (exit 2) from 2026-07-29 until 2026-07-30. Measured over
# that window (docs/backlog.md REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01):
# 78 REVIEW_RECORD_GATE_OVERRIDE events in
# ~/.claude/state/review-record-gate-overrides.log (68 on 2026-07-29, 10 on
# 2026-07-30), and EVERY ONE of the ten from 2026-07-30 states the identical
# reason — a builder subagent has no Task/Agent-dispatch tool and so cannot
# itself invoke harness-reviewer, the gate's own prescribed remedy. That is a
# remedy-chain deadlock (ADR 059 D5 class): the gate demanded an action the
# actor it fires on is structurally unable to perform. The only two exits
# were "never commit" or "override" — not agent misconduct, a gate built at
# the wrong layer for the actor present there.
#
# adapters/claude-code/doctrine/deterministic-process.md Rule 1: enforce at
# the narrowest CHOKEPOINT EVERY PATH TRAVERSES. This PreToolUse hook is a
# convenient layer, not the funnel — cherry-pick/rebase/amend/commit-time-
# override all reach `git push` regardless. The funnel is `git push` itself,
# and — separately from the funnel argument — it is ALSO the right layer on
# remedy-reachability grounds: the actor at push time is the ORCHESTRATOR
# (scripts/estate-merge.sh's real push, or an operator's own push), which
# DOES have Task/Agent-dispatch capability. Enforcement belongs where the
# required action is possible.
#
# So: hooks/review-record-push-gate.sh (wired via git-hooks/pre-push, the
# same core.hooksPath dispatcher pre-push-divergence-check.sh and
# pre-push-test-gate.sh already use) is now AUTHORITATIVE. THIS gate stays —
# per the operator's explicit direction, "the commit-time gate STAYS as fast
# early feedback" — but it no longer blocks: it prints the exact same
# detection (uncovered in-surface files) as a WARNING and always exits 0.
# A builder with no dispatch tool can now commit and make forward progress
# without ever touching an override; the SAME content is still refused when
# it actually tries to reach the remote, because nothing downstream reviewed
# it yet. Golden scenario REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01 is
# asserted across TWO files: this file's self-test Scenario 1b ("GOLDEN —
# REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01") proves forward progress with no
# override set; hooks/review-record-push-gate.sh's Scenario 1 proves the same
# content is still refused at push.
#
# The REVIEW_RECORD_GATE_OVERRIDE escape hatch (env var, no operator
# authorization checked — deterministic-process.md Rule 2's own counter-
# example) is REMOVED from this file: there is nothing left to override once
# the gate never blocks. It is NOT honored at the push-gate layer either —
# that gate requires a SEPARATE, operator-authorized, SHA-scoped marker
# (scripts/authorize-review-record-push-override.sh), because Rule 2
# requires the authorization artifact at the layer that actually enforces.
#
# ============================================================================
# THE GAP THIS ORIGINALLY CLOSED (golden case, PROVEN, 2026-07-29 history)
# ============================================================================
# 2026-07-28, commit f6562b2: a session wrote adapters/claude-code/hooks/lib/
# admission-lib.sh (664 lines, spliced into three live dispatch paths), committed
# it, and pushed it to master with NO harness-reviewer and NO task-verifier.
# When both were finally run they returned REJECT and FAIL respectively, on a
# deliverable that was already on master: a parser that returned 3379 for a true
# value of 3, a self-test whose headline "38/0" was only reproducible on a
# machine where the feature did not work, a "spawn-free ~0 ms" claim that
# measured 70.8 ms, and an ADM_STATE_DIR environment channel that silently
# bypassed the HALT kill switch.
#
# review-before-deploy.md already required a harness-reviewer PASS. It had TWO
# carriers, both at DEPLOY time: install.sh (hard block) and
# session-start-auto-install.sh (fail-open warn). Neither runs at COMMIT time,
# so f6562b2 sailed through and reached origin/master unreviewed.
# harness-reviewer's own words on 2026-07-28: wiring the commit-time carrier is
# "the single most important thing to fix", and the enforcement API
# (rrg_in_surface / rrg_is_covered) plus scripts/write-review-record.sh already
# existed, unwired.
#
# This hook WAS that carrier, and blocked (exit 2) from 2026-07-29 to
# 2026-07-30 at the operator's explicit direction ("Why are you suggesting
# warn mode? If it's valuable, then build and deploy it"). Superseded by "THE
# 2026-07-30 DEMOTION" above: hooks/review-record-push-gate.sh is now the one
# that blocks; this file's evidence-bar fields below are historical.
#
# ============================================================================
# CONSTITUTION §10 EVIDENCE BAR (historical — this gate no longer blocks; see
# hooks/review-record-push-gate.sh's own header for the current evidence bar)
# ============================================================================
#   GOLDEN SCENARIO : commit f6562b2 above. Self-test scenario 1 replays that
#                     exact staged set and now asserts it is DETECTED
#                     (advisory warning printed) and ALLOWED (rc=0).
#   FP EXPECTATION  : measured retroactively — scripts/measure-review-gate-fp.sh
#                     replays this gate's predicate over historical commits.
#                     Moot for false-positives now (advisory never blocks),
#                     kept for the detection-accuracy signal it still gives.
#   RETIREMENT      : this file retires (or shrinks to a thin wrapper) once
#                     every builder session gains Task/Agent-dispatch
#                     capability, closing the deadlock this demotion worked
#                     around at its actual root cause.
#
# ============================================================================
# WHAT IT WARNS ON, AND WHAT IT DELIBERATELY DOES NOT (never blocks, either way)
# ============================================================================
# WARNS: a `git commit` when a STAGED, ADDED-OR-MODIFIED file is in-surface
# for harness review (rrg_in_surface: hooks/*.sh, scripts/*.sh, agents/*.md
# top-level, config/*, manifest.json, settings.json.template, rules/*) and
# its blob is NOT covered by a grandfather entry or a PASS record. The commit
# still proceeds (rc=0) — this is advisory-only; see "THE 2026-07-30
# DEMOTION" above for why.
#
# NEVER WARNS (same false-positive budget the blocking version measured, kept
# because a noisy advisory is still a cost even though it cannot block):
#   1. No staged in-surface file           -> silent allow, the common case.
#   2. Pure DELETIONS                       -> a removed file has no blob to
#      review; --diff-filter excludes D.
#   3. Mid-rebase / mid-merge / cherry-pick -> irrelevant to warn about;
#      .git/REBASE_HEAD, MERGE_HEAD, CHERRY_PICK_HEAD short-circuit.
#   4. Not a git repo, no git, no jq        -> fail-open, never brick a machine.
#   5. Bootstrap                            -> rrg_is_covered itself fail-opens
#      when NEITHER coverage file exists on the checkout (Amendment E).
#   6. A record staged in the SAME commit   -> coverage is read with ref="" (the
#      working tree/index), so fixing the review and committing together works.
#
# REMEDY: writing a record via scripts/write-review-record.sh is the same
# remedy as before; it is no longer REQUIRED to commit (this gate never
# blocks), only to satisfy hooks/review-record-push-gate.sh before the
# content can reach master/main.
#
# REMOVED 2026-07-30: the REVIEW_RECORD_GATE_OVERRIDE escape hatch. It existed
# to waive a BLOCK; there is no block left here to waive. It is deliberately
# NOT honored at hooks/review-record-push-gate.sh either — Rule 2 of
# deterministic-process.md requires an operator-authorized artifact at the
# layer that actually enforces (scripts/authorize-review-record-push-
# override.sh), not an inline env var an agent can set unilaterally.
#
# Self-test: bash review-record-commit-gate.sh --self-test
# ============================================================================

set -uo pipefail

_RRCG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ============================================================================
# COMMAND PARSING — DELEGATED, NOT HAND-ROLLED (class fix, 2026-07-29)
# ============================================================================
# This hook used to carry its own `git commit` detector: a `${rest//&&/$'\n'}`
# string substitution over the RAW command, a segment walk that took the first
# bare token after `-C`, and no quote handling at all. harness-reviewer REJECTED
# it three times; each round the builder fixed the one shape demonstrated and
# shipped the CLASS. Seven PROVEN fail-opens remained (quoted -C, single-quoted
# -C, unexpanded-variable -C, `cd <harness> &&` from a foreign cwd, `pushd`,
# `--git-dir/--work-tree`, `cd <harness>;`) plus one over-fire (a `;` inside a
# quoted string manufactured a phantom command segment).
#
# All of it was already solved, correctly, in scope-enforcement-gate.sh — which
# runs in the SAME PreToolUse Bash chain. That parser is now extracted to
# lib/git-command-parse.sh and BOTH gates use it. There is ONE commit-target
# resolver in this harness. Do not add a second one here.
# ============================================================================
# shellcheck source=/dev/null
source "$_RRCG_SELF_DIR/lib/git-command-parse.sh" 2>/dev/null || true

# This writer is HOST-LOCAL — it is not one of the shared libs, so it carried no
# REMOVED 2026-07-30: _rrcg_log_override (and the REVIEW_RECORD_GATE_OVERRIDE
# escape hatch it served) — this gate no longer blocks, so there is nothing
# left to override. ~/.claude/state/review-record-gate-overrides.log remains
# on disk as a historical audit trail of the 78 pre-demotion override events
# (docs/backlog.md REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01); nothing writes
# to it anymore.
#
# NOTE ON `push`: it was REMOVED from the verb set (harness-review Major). The
# push arm checked the INDEX, which is the wrong subject — it blocked pushes over
# unrelated staged work while giving zero protection against pushing
# already-committed unreviewed changes, which is literally the golden case's
# final step. A correct push arm must diff @{u}..HEAD; until that is built,
# matching push is pure cost. Tracked in the manifest honest_status.
#
# Commit detection and target resolution now live entirely in
# lib/git-command-parse.sh (gcp_resolve_commit_target). See the banner above.

# _rrcg_is_harness_repo <root> — this gate is specific to the harness repo.
# Without this, ANY repo containing scripts/*.sh plus a docs/reviews/records/
# dir was gated (harness-review Major); only rrg's bootstrap fail-open was
# hiding it.
# Is the coverage index staged, or does it exist only in the worktree?
# Returns 0 (fine) when the file is unmodified vs the index — i.e. nothing new
# to stage — and 0 when it IS staged. Returns 1 when the worktree copy differs
# from the index copy, which is exactly "the record you are relying on is not in
# this commit".
#
# CALLER CONTRACT (harness-review Critical, 2026-07-29): only call this when at
# least one staged in-surface file was ACTUALLY covered by a record. It used to
# run unconditionally on the uncovered==0 path, so a docs-only commit that
# consulted ZERO coverage was blocked whenever index.json happened to have local
# edits — and the block message asserted "coverage is satisfied by ... your
# WORKING TREE", a reason the code had never established. See covered_count in
# _rrcg_main.
#
# BAILOUTS RESOLVE TOWARD BLOCK (the file's own principle, applied). Both git
# probes below used to `|| return 0` — i.e. "if I cannot tell whether the record
# is in the commit, authorize the commit". That is backwards for a gate: an
# unreadable or untracked index.json means the record demonstrably is NOT in the
# index, which is the exact condition this check exists to catch.
_rrcg_record_is_staged() {
  local repo_root="$1" rel="docs/reviews/records/index.json"
  # Genuinely not applicable (not a bailout): with no index.json on disk the
  # coverage that satisfied the gate came from grandfather-manifest.json, which
  # is committed. There is no working-tree-only record to strand.
  [[ -f "$repo_root/$rel" ]] || return 0
  local idx wt
  # Not in the index at all (untracked, or staged-for-deletion) -> it cannot be
  # part of this commit.
  idx="$(git -C "$repo_root" rev-parse ":$rel" 2>/dev/null)" || return 1
  wt="$(git -C "$repo_root" hash-object "$repo_root/$rel" 2>/dev/null)" || return 1
  [[ "$idx" == "$wt" ]]
}

_rrcg_is_harness_repo() {
  [[ -f "$1/adapters/claude-code/manifest.json" ]]
}

# _rrcg_advisory_message — ADVISORY ONLY (2026-07-30 demotion). This commit
# is NOT blocked; the message is printed and the commit proceeds regardless.
# hooks/review-record-push-gate.sh is the gate that actually enforces before
# this content can reach master/main.
_rrcg_advisory_message() {
  local repo_root="$1"; shift
  local files=("$@")
  {
    echo "================================================================"
    echo "REVIEW-RECORD GATE — ADVISORY (commit NOT blocked)"
    echo "================================================================"
    echo
    echo "These staged files change harness BEHAVIOR and have no review record"
    echo "yet. This commit proceeds anyway — this gate is advisory-only since"
    echo "2026-07-30 (a builder subagent typically has no Task/Agent-dispatch"
    echo "tool and cannot itself invoke harness-reviewer; docs/backlog.md"
    echo "REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01). The push to master/main"
    echo "IS still enforced — hooks/review-record-push-gate.sh will refuse it"
    echo "until one of the files below is reviewed and recorded:"
    local f
    for f in "${files[@]}"; do echo "  • $f"; done
    echo
    echo "Why review-record coverage exists at all: on 2026-07-28 commit"
    echo "f6562b2 put a 664-line lib onto master with no harness-reviewer."
    echo "Both reviewers, run afterwards, returned REJECT and FAIL — a parser"
    echo "that read 3379 for a true value of 3, a self-test that only passed"
    echo "where the feature did not work, and an environment variable that"
    echo "silently bypassed the HALT kill switch."
    echo
    echo "TO SATISFY THE PUSH GATE BEFORE YOU (or the orchestrator) PUSH THIS:"
    echo
    echo "  1. Dispatch harness-reviewer on this change and get a verdict."
    echo "     (The orchestrator has Task/Agent-dispatch capability even when"
    echo "     this builder session does not — that is WHY enforcement moved"
    echo "     to push time; see hooks/review-record-push-gate.sh.)"
    echo
    echo "  2. Record the verdict:"
    echo "       bash adapters/claude-code/scripts/write-review-record.sh capture \\"
    echo "         --kind harness-change-review --reviewer harness-reviewer \\"
    echo "         --verdict PASS --plan-ref <plan> --quote '<verdict sentence>' \\"
    for f in "${files[@]}"; do echo "         --file $f \\"; done
    echo "         --commit-sha PENDING"
    echo
    echo "  3. Stage the record and commit/push again. Coverage is read from"
    echo "     the commit content, so the record can land in the same push."
    echo "================================================================"
  } >&2
}

_rrcg_main() {
  local input; input="$(cat 2>/dev/null || true)"
  [[ -n "$input" ]] || return 0

  command -v jq >/dev/null 2>&1 || return 0    # fail-open: no jq, no gate

  local tool cmd
  tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  # PowerShell runs `git commit` too, and its `cd` is a Set-Location alias — both
  # of which the shared resolver understands. Gating only Bash left the same
  # silent bypass HARNESS-GAP-47 closed for scope-enforcement-gate in 2026-06.
  [[ "$tool" == "Bash" || "$tool" == "PowerShell" ]] || return 0
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true)"
  [[ -n "$cmd" ]] || return 0

  # The shared resolver is load-bearing. If it is missing we cannot tell a commit
  # from a mention; the gate has nothing to stand on, so pass through (documented
  # fail-open class 4 — never brick a machine) but say so on stderr rather than
  # dying silently.
  if ! command -v gcp_resolve_commit_target >/dev/null 2>&1; then
    echo "review-record-commit-gate: lib/git-command-parse.sh unavailable — gate skipped." >&2
    return 0
  fi
  gcp_resolve_commit_target "$cmd" "$PWD"

  # Introspection for the standing CROSS-GATE AGREEMENT test (round 5). Prints
  # what THIS gate concluded, through the path it really uses, then exits.
  if [[ "${SCOPE_PRINT_TARGET:-0}" == "1" ]]; then
    printf '%s|%s\n' "${GCP_IS_COMMIT:-0}" "${GCP_TARGET_DIR:-}"
    return 0
  fi

  if [[ "${GCP_IS_COMMIT:-0}" -ne 1 ]]; then
    # BAILOUT RESOLVES TOWARD BLOCK: a degraded parse means "I could not tell",
    # not "it is not a commit". Fall through to the coverage check, which only
    # blocks if unreviewed harness content is genuinely staged.
    [[ "${GCP_PARSE_DEGRADED:-0}" -eq 1 ]] || return 0
    echo "review-record-commit-gate: command parse degraded — checking coverage anyway." >&2
  fi

  command -v git >/dev/null 2>&1 || return 0
  local repo_root="" target="${GCP_TARGET_DIR:-}"
  # NOTE: the two bare `git rev-parse` calls below run BEFORE repo_root is known
  # and deliberately take the process cwd as their subject — that is the thing
  # being resolved. Every git call AFTER this point takes -C "$repo_root".
  if [[ -n "$target" ]]; then
    repo_root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || repo_root=""
    # BAILOUT RESOLVES TOWARD BLOCK, BUT ONLY WHEN THE TARGET IS GENUINELY
    # UNKNOWN (round-5 M1).
    #
    # Round 4 fell back to the cwd for EVERY unresolvable target, with the
    # claimed justification "falling back to the cwd cannot over-fire: if the
    # cwd is not a harness repo the identity check below allows anyway". That
    # claim is false whenever the cwd IS the harness repo — which is the normal
    # case. PROVEN over-fire: `W=/other/repo; git -C "$W" commit` blocked a
    # commit aimed at an unrelated repo, citing whatever harness file happened
    # to be staged here.
    #
    # The distinction that matters is whether we KNOW where the commit is going.
    # The resolver now substitutes inline assignments, so `$W` above resolves to
    # /other/repo — a concrete path. A concrete path that is not a repo means the
    # real `git commit` will fail on its own; there is nothing to scope-check,
    # and this gate declines (the same posture scope-enforcement-gate has always
    # taken for a nonexistent target). Only a target still carrying an
    # UNRESOLVED `$` is genuinely unknown, and only that falls back to the cwd —
    # which keeps the round-3 fail-open for `git -C $REPO commit` closed.
    if [[ -z "$repo_root" ]]; then
      case "$target" in
        *'$'*)
          repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || repo_root="" ;;
        *)
          return 0 ;;
      esac
    fi
  else
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || repo_root=""
  fi
  [[ -n "$repo_root" ]] || return 0
  # Harness-repo identity: this gate governs THIS harness's in-surface files.
  _rrcg_is_harness_repo "$repo_root" || return 0

  # Exemption 3: never interrupt an in-progress rebase/merge/cherry-pick.
  # -C "$repo_root", NOT the cwd (harness-review Major, 2026-07-29). Reading the
  # CWD's git-dir cut both ways: a rebase in some unrelated repo you happened to
  # be standing in DISARMED the gate for a commit targeting the harness, and a
  # genuine rebase in the target repo did NOT exempt it, stranding the operator
  # mid-rebase with no way forward.
  local gitdir
  gitdir="$(git -C "$repo_root" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir=""
  if [[ -z "$gitdir" ]]; then
    # --absolute-git-dir predates git 2.13; fall back and resolve by hand.
    gitdir="$(git -C "$repo_root" rev-parse --git-dir 2>/dev/null)" || gitdir=""
    case "$gitdir" in
      ""|/*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
      *) gitdir="$repo_root/$gitdir" ;;
    esac
  fi
  if [[ -n "$gitdir" ]]; then
    for m in REBASE_HEAD MERGE_HEAD CHERRY_PICK_HEAD; do
      [[ -e "$gitdir/$m" ]] && return 0
    done
    [[ -d "$gitdir/rebase-merge" || -d "$gitdir/rebase-apply" ]] && return 0
  fi

  # review-independence plan RI1b (docs/plans/review-independence.md):
  # "committing IS enqueueing" -- the authoring session never decides to
  # enqueue a review; attempting to commit uncovered in-surface content IS
  # the enqueue trigger. Placed BEFORE the override check below and BEFORE
  # the uncovered-computation this function does further down, deliberately
  # unconditional: an overridden commit still needs independent review just
  # as much as a blocked one, so this must not depend on which exit path
  # this function eventually takes. Fail-open, always -- a bug here can
  # never affect this gate's exit code (rq_auto_enqueue_uncovered swallows
  # every internal failure and never propagates a non-zero return that
  # matters to this caller, which does not check it).
  source "$_RRCG_SELF_DIR/lib/review-queue-auto-enqueue-lib.sh" 2>/dev/null
  if command -v rq_auto_enqueue_uncovered >/dev/null 2>&1; then
    rq_auto_enqueue_uncovered "$repo_root" 2>/dev/null
  fi

  # REMOVED 2026-07-30: the REVIEW_RECORD_GATE_OVERRIDE escape-hatch branch.
  # This gate never blocks any more (see header), so an override has nothing
  # left to waive — keeping it would be exactly the "step nothing invokes
  # changes anything" theatre adapters/claude-code/doctrine/
  # deterministic-process.md Rule 3 names. REVIEW_RECORD_GATE_OVERRIDE is
  # deliberately NOT read by hooks/review-record-push-gate.sh either (Rule 2:
  # that authoritative layer requires scripts/authorize-review-record-push-
  # override.sh's operator-authorized, sha-scoped marker instead).

  # shellcheck source=/dev/null
  source "$_RRCG_SELF_DIR/lib/review-record-gate-lib.sh" 2>/dev/null || return 0
  command -v rrg_in_surface >/dev/null 2>&1 || return 0
  command -v rrg_is_covered >/dev/null 2>&1 || return 0

  # Exemption 2: ACMR excludes deletions — a removed blob cannot be reviewed.
  local staged
  staged="$(git -C "$repo_root" diff --cached --name-only --diff-filter=ACMR 2>/dev/null)" || return 0
  [[ -n "$staged" ]] || return 0    # exemption 1: nothing staged

  local -a uncovered=()
  local path sha covered_count=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    rrg_in_surface "$path" || continue
    # THE INDEX, NOT THE WORKING TREE (harness-review Critical, 2026-07-29).
    # rrg_blob_sha_of_file hashes the FILESYSTEM, but `git commit` commits the
    # INDEX. The reviewer staged unreviewed content, restored the worktree to a
    # covered blob, and the commit sailed through rc=0 — the gate attested to
    # bytes it never read. It also fails the other way: stage the reviewed
    # version, keep editing, and the commit is wrongly blocked.
    sha="$(git -C "$repo_root" rev-parse ":$path" 2>/dev/null)" || sha=""
    [[ -n "$sha" ]] || continue
    # ref="" => read coverage from the WORKING TREE/index, so a record staged in
    # this same commit counts (exemption 6 — makes the gate satisfiable in one pass).
    # Coverage is read from the WORKING TREE (ref=""), which is what
    # rrg_is_covered supports — the lib has no index mode (it branches to `cat`
    # on an empty ref and to `git show <ref>:<path>` otherwise, so there is no
    # way to ask it for `:<path>`). The blob, correctly, comes from the index.
    # harness-reviewer flagged the asymmetry: an UNSTAGED record satisfies the
    # gate, so the change could land with no record actually in the commit and a
    # later `git clean` would discard the only evidence. Rather than fork the
    # lib, that hole is closed explicitly below (_rrcg_record_is_staged).
    if ! rrg_is_covered "$repo_root" "" "$path" "$sha"; then
      uncovered+=("$path")
    else
      covered_count=$((covered_count+1))
    fi
  done <<< "$staged"

  # The record that satisfies coverage must itself be STAGED, or it is not part
  # of the commit the gate just authorized (harness-reviewer Major, 2026-07-29).
  #
  # GATED ON covered_count > 0 (harness-review Critical, 2026-07-29). This ran
  # unconditionally, so a docs-only commit — which consults no coverage at all —
  # was blocked whenever index.json merely had unstaged local edits, and was told
  # "coverage is satisfied by ... your WORKING TREE", a reason that had never been
  # established. The check is only meaningful when a record actually did the
  # satisfying.
  if [[ "${#uncovered[@]}" -eq 0 ]]; then
    if [[ "$covered_count" -gt 0 ]] && ! _rrcg_record_is_staged "$repo_root"; then
      {
        echo "================================================================"
        echo "REVIEW-RECORD GATE — ADVISORY: record not staged"
        echo "================================================================"
        echo "$covered_count staged in-surface file(s) are covered ONLY by"
        echo "docs/reviews/records/index.json as it exists in your WORKING TREE."
        echo "That file is not staged, so it will NOT be part of this commit: the"
        echo "change would land with no review record in the tree, and a later"
        echo "\`git clean -fd\` or worktree teardown would discard the only evidence."
        echo "This commit proceeds anyway (advisory-only, see header) — but"
        echo "hooks/review-record-push-gate.sh will re-derive coverage at push"
        echo "time and will NOT see this unstaged record either."
        echo ""
        echo "FIX (separate call): git add docs/reviews/records/"
        echo "================================================================"
      } >&2
      # ADVISORY ONLY — see header "THE 2026-07-30 DEMOTION". Never blocks.
      return 0
    fi
    return 0
  fi

  # ledger_emit lives in lib/signal-ledger.sh, which this hook never sourced —
  # so the guard was ALWAYS false and no block was ever recorded (harness-review
  # Major: write-only observability). Source it, then emit.
  source "$_RRCG_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true
  command -v ledger_emit >/dev/null 2>&1 && \
    # "warn" (not a new "advisory" vocabulary word) -- reuses the EXISTING
    # signal-ledger event-type taxonomy (observability-consumer-map.json)
    # rather than introducing a new one that would need its own consumer
    # entries; semantically this commit-time gate is exactly a warn now.
    ledger_emit "review-record-commit-gate" "warn" "files=${#uncovered[@]}"
  _rrcg_advisory_message "$repo_root" "${uncovered[@]}"
  # ADVISORY ONLY (2026-07-30 demotion) — this gate never blocks; the
  # authoritative enforcement is hooks/review-record-push-gate.sh at push
  # time. See this file's header "THE 2026-07-30 DEMOTION" for why.
  return 0
}

# ===========================================================================
# Self-test
# ===========================================================================
_rrcg_self_test() {
  local PASS=0 FAIL=0
  pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
  fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }

  local T; T="$(mktemp -d)" || { echo "cannot mktemp"; return 1; }
  # ABSOLUTE — every scenario below runs the gate from inside a temp repo, so a
  # relative ${BASH_SOURCE[0]} resolves to nothing there and every scenario
  # returns 127 (command not found) while LOOKING like a gate failure.
  local SELF="$_RRCG_SELF_DIR/$(basename "${BASH_SOURCE[0]}")"

  # a throwaway repo with the coverage files present, so we exercise real
  # non-coverage rather than rrg's bootstrap fail-open
  local R="$T/repo"
  mkdir -p "$R/adapters/claude-code/hooks/lib" "$R/docs/reviews/records"
  # The fixture must LOOK like the harness repo: _rrcg_is_harness_repo keys on
  # adapters/claude-code/manifest.json (added 2026-07-29 so the gate stops
  # governing unrelated repos). Without this every scenario silently allows.
  printf '{"schema_version":1,"entries":[]}\n' > "$R/adapters/claude-code/manifest.json"
  ( cd "$R" && git init -q . && git config user.email t@example.com && git config user.name T \
      && git config core.hooksPath "" ) >/dev/null 2>&1
  cp "$_RRCG_SELF_DIR/lib/review-record-gate-lib.sh" "$R/adapters/claude-code/hooks/lib/" 2>/dev/null
  printf '{"records":[]}\n' > "$R/docs/reviews/records/index.json"
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/grandfather-manifest.json"
  ( cd "$R" && git add -A && git commit -qm init ) >/dev/null 2>&1

  run() { # $1 = command string; echoes rc
    # Build the JSON with jq, not printf: a command containing double quotes
    # (`git commit -m "feat: x"` — the overwhelmingly common real shape) makes a
    # printf-built payload INVALID JSON, jq rejects it, and the gate fail-opens.
    # The first draft of this suite used printf and its golden case silently
    # "passed the gate" for that reason alone.
    local payload
    payload="$(jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}')"
    printf '%s' "$payload" | ( cd "$R" && bash "$SELF" ) >/dev/null 2>&1
    echo $?
  }

  # run_capture <command-string> -- echoes rc; sets global RUN_MSG to stderr.
  # ADVISORY-demotion note: this gate is rc=0 on every path now, so "does the
  # detection actually fire" can no longer be read off the exit code — every
  # scenario below that used to assert rc=2 now asserts rc=0 (never blocks)
  # AND checks RUN_MSG for the specific advisory text, so a regression that
  # silently stops detecting uncovered content (as opposed to one that merely
  # stops blocking, which is now correct) still turns these tests RED.
  # NOT invoked via `x="$(run_capture ...)"` -- that would run the whole
  # function in a subshell (command substitution forks one), and RUN_MSG
  # assigned inside would never propagate back out. Call it as a plain
  # statement; read RUN_RC / RUN_MSG (true globals) afterward.
  run_capture() {
    local payload
    payload="$(jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}')"
    RUN_MSG="$(printf '%s' "$payload" | ( cd "$R" && bash "$SELF" ) 2>&1 1>/dev/null)"
    RUN_RC=$?
  }

  echo "Scenario 1: GOLDEN CASE — staging an unreviewed hooks/lib/*.sh is DETECTED and ALLOWED (advisory)"
  mkdir -p "$R/adapters/claude-code/hooks/lib"
  echo '# unreviewed harness change' > "$R/adapters/claude-code/hooks/lib/admission-lib.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  local rc
  run_capture 'git commit -m "feat: admission lib"'
  rc="$RUN_RC"
  [[ "$rc" == "0" ]] && pass "f6562b2-shaped commit ALLOWED (rc=0, advisory-only since 2026-07-30)" || fail "expected rc 0, got $rc — the commit-time gate must never block any more"
  case "$RUN_MSG" in *admission-lib.sh*) pass "advisory message still names the offending file" ;; *) fail "detection silently stopped firing — advisory message omits the file" ;; esac

  echo "Scenario 1b (GOLDEN — REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01): a builder with NO"
  echo "  Task/Agent-dispatch tool and NO override set makes forward progress at commit time"
  ( cd "$R" && git reset -q ) >/dev/null 2>&1
  echo '# unreviewed harness change, no dispatch tool available' > "$R/adapters/claude-code/hooks/lib/no-dispatch-tool.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/no-dispatch-tool.sh ) >/dev/null 2>&1
  rc="$(unset REVIEW_RECORD_GATE_OVERRIDE; run 'git commit -m "feat: cannot invoke harness-reviewer here"')"
  [[ "$rc" == "0" ]] && pass "GOLDEN: commit succeeds with NO override set — the builder deadlock is resolved" \
    || fail "GOLDEN REGRESSION: a builder with no dispatch tool and no override is still blocked (rc=$rc)"

  echo "Scenario 2: the advisory message names the file, the remedy, AND says the commit is NOT blocked"
  ( cd "$R" && git reset -q ) >/dev/null 2>&1
  ( cd "$R" && git add adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  run_capture 'git commit -m x'
  rc="$RUN_RC"
  local msg="$RUN_MSG"
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  case "$msg" in *admission-lib.sh*) pass "message names the offending file" ;; *) fail "message omits the file" ;; esac
  case "$msg" in *write-review-record.sh*) pass "message names the exact remedy command" ;; *) fail "message omits the remedy" ;; esac
  case "$msg" in *"ADVISORY"*) pass "message is clearly labeled ADVISORY" ;; *) fail "ADVISORY label missing"; esac
  case "$msg" in *"review-record-push-gate.sh"*) pass "message points at the authoritative push gate" ;; *) fail "message omits the authoritative-gate pointer"; esac
  case "$msg" in *"REVIEW_RECORD_GATE_OVERRIDE"*) fail "message still advertises the removed REVIEW_RECORD_GATE_OVERRIDE escape hatch" ;; *) pass "message does not advertise a removed mechanism"; esac

  echo "Scenario 3: FP budget — a NON-surface file does not block"
  ( cd "$R" && git reset -q ) >/dev/null 2>&1
  mkdir -p "$R/docs"; echo 'notes' > "$R/docs/notes.md"
  ( cd "$R" && git add docs/notes.md ) >/dev/null 2>&1
  rc="$(run 'git commit -m "docs: notes"')"
  [[ "$rc" == "0" ]] && pass "docs-only commit allowed" || fail "docs-only commit blocked (rc=$rc) — false positive"

  echo "Scenario 4: FP budget — nothing staged at all"
  ( cd "$R" && git reset -q ) >/dev/null 2>&1
  rc="$(run 'git commit -m "empty"')"
  [[ "$rc" == "0" ]] && pass "no staged files -> allowed" || fail "blocked with empty index (rc=$rc)"

  echo "Scenario 5: FP budget — a pure DELETION of an in-surface file"
  ( cd "$R" && git add -A && git commit -qm "add for deletion test" ) >/dev/null 2>&1
  ( cd "$R" && git rm -q adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  rc="$(run 'git commit -m "chore: remove lib"')"
  [[ "$rc" == "0" ]] && pass "deletion-only commit allowed (no blob to review)" || fail "deletion blocked (rc=$rc) — false positive"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1

  echo "Scenario 6: FP budget — non-commit git commands are untouched"
  echo '# x' > "$R/adapters/claude-code/hooks/lib/other.sh"
  ( cd "$R" && git add -A ) >/dev/null 2>&1
  for c in 'git status' 'git diff --cached' 'git log --oneline -5' 'ls -la'; do
    rc="$(run "$c")"
    [[ "$rc" == "0" ]] && pass "allowed: $c" || fail "blocked a non-commit command: $c (rc=$rc)"
  done

  echo "Scenario 7: mid-rebase is never interrupted"
  local gd; gd="$(cd "$R" && git rev-parse --git-dir)"
  : > "$R/$gd/REBASE_HEAD" 2>/dev/null || : > "$gd/REBASE_HEAD" 2>/dev/null
  rc="$(run 'git commit -m "during rebase"')"
  [[ "$rc" == "0" ]] && pass "commit during rebase allowed" || fail "blocked mid-rebase (rc=$rc) — would strand the operator"
  rm -f "$R/$gd/REBASE_HEAD" "$gd/REBASE_HEAD" 2>/dev/null

  echo "Scenario 8: REVIEW_RECORD_GATE_OVERRIDE is INERT — proven by STDERR DIFFERENTIAL, not by rc"
  # RETIRED 2026-07-30 (was: "escape hatch requires a REASON, and is logged").
  # The override branch this scenario tested no longer exists — the commit
  # never blocks regardless, so there is nothing left to waive.
  #
  # REWRITTEN 2026-07-30 (harness-reviewer M2). The previous version asserted
  # rc=0 on a gate that ALWAYS exits 0, and said so in its own message ("as it
  # would be regardless") — a tautology, not a test. MUTATION-PROVEN vacuous:
  # resurrecting the branch as
  #     if [[ -n "${REVIEW_RECORD_GATE_OVERRIDE:-}" ]]; then return 0; fi
  # immediately before the REMOVED comment in _rrcg_main, writing no audit
  # log, left ALL FIVE of the old assertions passing.
  #
  # The observable the env var CAN still move is the ADVISORY BANNER this gate
  # prints to stderr for uncovered content. A resurrected early-return
  # suppresses it entirely. So the real invariant is a DIFFERENTIAL: with and
  # without the variable, stderr must be BYTE-IDENTICAL. Measured against the
  # mutant: 1937 bytes unset vs 0 bytes set — the assertion below fails, and
  # the mutant dies. Against the real gate: 1937 vs 1937.
  #
  # RE-DERIVE THE CONSTANT (do not hand-edit it — a quoted count with no
  # re-derivation command is exactly the drift class harness-reviewer M2 and
  # the MINOR of 2026-07-30 both caught; the previous value, 1923, was stale
  # and nothing re-checked it):
  #   bash adapters/claude-code/hooks/review-record-commit-gate.sh --self-test \
  #     | grep -oE '\([0-9]+ bytes\)'
  # Verified 1937 on BOTH /bin/bash 3.2.57 and /opt/homebrew/bin/bash 5.3.15
  # (2026-07-30). The number is illustrative of the differential's magnitude,
  # not an assertion — the test compares the two runs to each other.
  rm -f "$T/ovr.log" 2>/dev/null

  # Stage UNCOVERED in-surface content so the advisory banner has a reason to
  # fire; an empty index makes the differential observable rather than vacuous
  # in a second, quieter way.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# unreviewed, for the differential' > "$R/adapters/claude-code/hooks/lib/differential.sh"
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add -A ) >/dev/null 2>&1

  _rrcg_stderr_without() {
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
      | ( cd "$R" && env -u REVIEW_RECORD_GATE_OVERRIDE REVIEW_RECORD_GATE_LOG="$T/ovr.log" bash "$SELF" ) 2>&1 >/dev/null
  }
  _rrcg_stderr_with() {
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
      | ( cd "$R" && REVIEW_RECORD_GATE_LOG="$T/ovr.log" REVIEW_RECORD_GATE_OVERRIDE="$1" bash "$SELF" ) 2>&1 >/dev/null
  }

  local base_err; base_err="$(_rrcg_stderr_without)"
  if [[ -n "$base_err" ]]; then
    pass "baseline: the advisory banner IS emitted for uncovered content ($(printf '%s' "$base_err" | wc -c | tr -d ' ') bytes) — the differential below is observable"
  else
    fail "baseline: no advisory banner emitted, so the differential assertion would be vacuous"
  fi

  local v ovr_err
  for v in "" "production is down and this hotfix cannot wait for review" "x" "testing"; do
    ovr_err="$(_rrcg_stderr_with "$v")"
    if [[ "$ovr_err" == "$base_err" ]]; then
      pass "REVIEW_RECORD_GATE_OVERRIDE=\"$v\" -> stderr BYTE-IDENTICAL to unset (the var moves nothing)"
    else
      fail "REVIEW_RECORD_GATE_OVERRIDE=\"$v\" CHANGED the gate's output ($(printf '%s' "$base_err" | wc -c | tr -d ' ') -> $(printf '%s' "$ovr_err" | wc -c | tr -d ' ') bytes) — the removed branch is live again"
    fi
  done

  if [[ -f "$T/ovr.log" ]]; then
    fail "the retired override-audit log was written to — REVIEW_RECORD_GATE_OVERRIDE is not actually inert"
  else
    pass "no override audit log entry written — the mechanism is genuinely gone, not just unreachable"
  fi
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1

  echo "Scenario 9: coverage staged in the SAME commit satisfies the gate (one-pass fix)"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# reviewed change' > "$R/adapters/claude-code/hooks/lib/covered.sh"
  local blob; blob="$(cd "$R" && git hash-object adapters/claude-code/hooks/lib/covered.sh)"
  # Schema is the REAL one rrg_is_covered matches (lib :158-159): a flat
  # .entries[] of {path, blob_sha, kind, verdict} — not a nested records/files
  # shape. The first draft of this scenario invented the nested shape and failed,
  # which is the same author-written-fixture trap that hid two Critical parser
  # defects in admission-lib a day earlier.
  printf '{"entries":[{"path":"adapters/claude-code/hooks/lib/covered.sh","blob_sha":"%s","kind":"harness-change-review","verdict":"PASS"}]}\n' "$blob" \
    > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add -A ) >/dev/null 2>&1
  rc="$(run 'git commit -m "feat: reviewed change"')"
  [[ "$rc" == "0" ]] && pass "a PASS record staged alongside the change satisfies the gate" \
    || fail "blocked despite an in-index PASS record (rc=$rc) — the gate would be unsatisfiable in one pass"

  echo "Scenario 10: fail-open — not a git repo"
  rc="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | ( cd "$T" && bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "outside a git repo -> allowed (never brick)" || fail "blocked outside a repo (rc=$rc)"

  echo "Scenario 11: INDEX vs WORKING TREE — the Critical the reviewer proved (E10)"
  # Stage UNREVIEWED content, then restore the worktree to a COVERED blob. A gate
  # that hashes the filesystem says "covered" and lets unreviewed bytes through.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# reviewed good' > "$R/adapters/claude-code/hooks/lib/covered.sh"
  local goodblob; goodblob="$(cd "$R" && git hash-object adapters/claude-code/hooks/lib/covered.sh)"
  printf '{"entries":[{"path":"adapters/claude-code/hooks/lib/covered.sh","blob_sha":"%s","kind":"harness-change-review","verdict":"PASS"}]}\n' "$goodblob" \
    > "$R/docs/reviews/records/index.json"
  echo '# EVIL unreviewed' > "$R/adapters/claude-code/hooks/lib/covered.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/covered.sh ) >/dev/null 2>&1   # stage EVIL
  echo '# reviewed good' > "$R/adapters/claude-code/hooks/lib/covered.sh"            # worktree back to GOOD
  run_capture 'git commit -m sneak'
  rc="$RUN_RC"
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  case "$RUN_MSG" in *covered.sh*) pass "staged-unreviewed + covered-worktree still DETECTED (gate reads the index, not the worktree)" ;; \
    *) fail "INDEX/WORKTREE HOLE: the sneaky staged content was never flagged — detection silently reads the worktree now"; esac
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1

  echo "Scenario 12: substring-as-intent — merely MENTIONING the phrase is not a commit (E13)"
  echo '# x' > "$R/adapters/claude-code/hooks/lib/mention.sh"
  ( cd "$R" && git add -A ) >/dev/null 2>&1
  local m
  for m in 'echo run git commit later' 'man git commit' 'grep -rn "git commit" docs/'; do
    rc="$(run "$m")"
    [[ "$rc" == "0" ]] && pass "allowed (mention only): $m" || fail "blocked a mere mention: $m (rc=$rc)"
  done
  run_capture 'git commit -m real'
  rc="$RUN_RC"
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  case "$RUN_MSG" in *mention.sh*) pass "a REAL commit in command position is still detected/warned" ;; \
    *) fail "anchoring broke the real case — mention.sh no longer flagged"; esac

  echo "Scenario 12b: a -C target from an EARLIER segment must not repoint the gate"
  # harness-reviewer proved four fail-open shapes where `git -C <path>` anywhere
  # in the raw command repointed repo_root at another repo; if that path was not
  # a harness repo (or did not exist) the gate returned 0 with an unreviewed blob
  # staged AND UNDETECTED. The worst was the orchestrator's OWN cherry-pick shape.
  # Now that this gate never blocks, "blocks despite a -C mention" becomes "warns
  # despite a -C mention" — rc=0 either way, so the message is the only signal
  # that detection actually ran against the CORRECT (harness) target.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# unreviewed' > "$R/adapters/claude-code/hooks/lib/leak.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/leak.sh ) >/dev/null 2>&1
  local _sib="$T/sibling"; mkdir -p "$_sib"
  ( cd "$_sib" && git init -q . && git config user.email t@example.com && git config user.name T ) >/dev/null 2>&1
  local _v; _v="$(printf 'git com''mit')"
  local _shape
  for _shape in \
    "git -C $_sib log --oneline -1 && git add -A && $_v -m x" \
    "git -C /no/such/path fetch && $_v -m x" \
    "echo \"git -C $_sib status\" && $_v -m x" \
    "$_v -m 'use git -C /tmp/other next time'"; do
    run_capture "$_shape"
    rc="$RUN_RC"
    [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc): $_shape"
    case "$RUN_MSG" in *leak.sh*) pass "detects despite a -C mention: ${_shape:0:46}..." ;; \
      *) fail "FAIL-OPEN (undetected): $_shape"; esac
  done

  echo "Scenario 13: foreign repo is not governed by this gate (E12)"
  local FR="$T/foreign"
  mkdir -p "$FR/scripts" "$FR/docs/reviews/records"
  ( cd "$FR" && git init -q . && git config user.email t@example.com && git config user.name T ) >/dev/null 2>&1
  printf '{"records":[]}\n' > "$FR/docs/reviews/records/index.json"
  echo '# deploy' > "$FR/scripts/deploy.sh"
  ( cd "$FR" && git add -A ) >/dev/null 2>&1
  rc="$(printf '%s' "$(jq -nc '{tool_name:"Bash",tool_input:{command:"git commit -m x"}}')" | ( cd "$FR" && bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "a non-harness repo with scripts/*.sh is NOT gated" || fail "gated a foreign repo (rc=$rc)"

  # ==========================================================================
  # Scenario 14: THE SEVEN PROVEN FAIL-OPENS (harness-reviewer probe B2-B4, C2-C5)
  # ==========================================================================
  # Every shape below reaches a `git commit` that targets THIS harness repo with
  # an unreviewed in-surface file staged. Each returned rc=0 before the shared
  # resolver landed — verified by running the probe against the pre-fix gate.
  # `runfrom` runs the gate from an arbitrary cwd, because the whole point of
  # four of these shapes is that the commit targets a repo the caller is not in.
  echo "Scenario 14: the seven PROVEN fail-opens must all still be DETECTED (was: BLOCK)"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  # Content must DIFFER from whatever earlier scenarios committed, or `git add`
  # stages nothing, `git diff --cached` is empty, and every shape below returns
  # rc=0 via exemption 1 — a green-looking suite that tested nothing.
  echo '# unreviewed change, scenario 14 marker' > "$R/adapters/claude-code/hooks/lib/admission-lib.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  ( cd "$R" && git diff --cached --quiet ) && fail "scenario 14 fixture staged NOTHING — the shapes below would all pass vacuously"
  local OUT="$T/outside"; mkdir -p "$OUT"
  runfrom() { # $1 = cwd, $2 = command string; echoes rc
    local payload
    payload="$(jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}')"
    printf '%s' "$payload" | ( cd "$1" && bash "$SELF" ) >/dev/null 2>&1
    echo $?
  }
  # Same subshell-scoping caveat as run_capture above -- call as a plain
  # statement, then read RUN_RC / RUN_MSG.
  runfrom_capture() { # $1 = cwd, $2 = command string; sets RUN_RC, RUN_MSG
    local payload
    payload="$(jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}')"
    RUN_MSG="$(printf '%s' "$payload" | ( cd "$1" && bash "$SELF" ) 2>&1 1>/dev/null)"
    RUN_RC=$?
  }
  # `git commit` is assembled at runtime so this suite's own source does not
  # contain the phrase in command position (the harness gates read hook source).
  # TWO forms are needed: CV for a segment that starts the command, SUB for the
  # bare subcommand where `git <flags>` is already written. Splicing CV after
  # `git -C <path>` yields `git -C <path> git commit`, which is NOT a commit —
  # the resolver correctly returns 0 and the scenario passes vacuously. That
  # exact mistake made four of these read as fail-opens during development.
  local CV SUB; CV="$(printf 'git com''mit')"; SUB="$(printf 'com''mit')"
  local _lbl _cwd _cmd
  while IFS='|' read -r _lbl _cwd _cmd; do
    [[ -n "$_lbl" ]] || continue
    runfrom_capture "$_cwd" "$_cmd"
    rc="$RUN_RC"
    [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc): $_lbl"
    case "$RUN_MSG" in *admission-lib.sh*) pass "DETECTS: $_lbl" ;; \
      *) fail "FAIL-OPEN (undetected): $_lbl"; esac
  done <<EOF
B2 git -C "quoted path"|$OUT|git -C "$R" $SUB -m x
B3 git -C 'single-quoted path'|$OUT|git -C '$R' $SUB -m x
B4 git -C \$REPO (unexpanded variable)|$R|git -C \$REPO $SUB -m x
C2 cd <harness> && commit, from a NON-harness cwd|$OUT|cd $R && $CV -m x
C3 pushd <harness> && commit|$OUT|pushd $R && $CV -m x
C4 --git-dir/--work-tree from a non-harness cwd|$OUT|git --git-dir=$R/.git --work-tree=$R $SUB -m x
C5 cd <harness>; commit (semicolon)|$OUT|cd $R; $CV -m x
EOF

  echo "Scenario 15: over-fire budget — a separator INSIDE a quoted string (F1)"
  # `echo "step: stage; git commit -m msg" >> notes.md` writes a note. The old
  # quote-blind `${rest//;/...}` split manufactured a phantom `git commit`
  # segment from the middle of the string and blocked the echo outright.
  rc="$(runfrom "$R" "echo \"step: stage; $CV -m msg\" >> notes.md")"
  [[ "$rc" == "0" ]] && pass "quoted separator does not manufacture a commit" \
    || fail "OVER-FIRE (rc=$rc): blocked an echo whose STRING contained '; git commit'"
  rc="$(runfrom "$R" "echo 'stage then $CV -m x'")"
  [[ "$rc" == "0" ]] && pass "single-quoted mention does not fire" || fail "OVER-FIRE (rc=$rc) on a single-quoted mention"

  echo "Scenario 16: record-staged check is gated on covered_count > 0"
  # NEGATIVE: a docs-only commit consults ZERO coverage. A dirty index.json in the
  # working tree is none of its business. This ran unconditionally and blocked,
  # asserting a "coverage is satisfied by your WORKING TREE" reason the code had
  # never established.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  mkdir -p "$R/docs"
  # UNIQUE content. `echo 'notes'` rewrote the same bytes an earlier scenario had
  # already committed, so `git add` staged nothing, the empty-index exemption
  # returned 0 first, and this scenario passed without ever reaching the check it
  # exists to test. The fixture assertion below makes that failure loud.
  echo 'notes for the covered_count negative case' > "$R/docs/notes.md"
  ( cd "$R" && git add docs/notes.md ) >/dev/null 2>&1
  ( cd "$R" && git diff --cached --quiet ) && fail "scenario 16 negative fixture staged NOTHING — it would pass vacuously"
  printf '{"entries":[{"path":"unrelated","blob_sha":"deadbeef","kind":"harness-change-review","verdict":"PASS"}]}\n' \
    > "$R/docs/reviews/records/index.json"        # dirty in the WORKTREE, NOT staged
  rc="$(run "$CV -m 'docs: notes'")"
  [[ "$rc" == "0" ]] && pass "docs-only commit + dirty index.json -> allowed (no coverage consulted)" \
    || fail "blocked a docs-only commit over an unrelated dirty index.json (rc=$rc)"
  # POSITIVE: when coverage IS what let the change through, the record must be in
  # the commit. Deleting the covered_count guard must NOT turn this green-by-luck.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# reviewed change' > "$R/adapters/claude-code/hooks/lib/covered.sh"
  local cblob; cblob="$(cd "$R" && git hash-object adapters/claude-code/hooks/lib/covered.sh)"
  printf '{"entries":[{"path":"adapters/claude-code/hooks/lib/covered.sh","blob_sha":"%s","kind":"harness-change-review","verdict":"PASS"}]}\n' "$cblob" \
    > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/covered.sh ) >/dev/null 2>&1   # stage the CHANGE only
  run_capture "$CV -m 'feat: covered but record unstaged'"
  rc="$RUN_RC"
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  case "$RUN_MSG" in *"record not staged"*|*"RECORD NOT STAGED"*) pass "covered-by-an-UNSTAGED-record still DETECTED as advisory (record must be in the commit to truly count)" ;; \
    *) fail "unstaged-record case no longer detected — advisory message silent"; esac
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1

  echo "Scenario 17: RETIRED — was 'the placeholder-waiver case actually fires'"
  # This scenario tested REVIEW_RECORD_GATE_OVERRIDE's placeholder-rejection
  # branch, which no longer exists (see Scenario 8). Nothing to test here any
  # more; kept as a numbered marker so the scenario count/history stays legible.

  echo "Scenario 18: rebase state is read from the TARGET repo, not the cwd"
  # A rebase in some unrelated repo you happen to be standing in must NOT
  # silently disarm detection for a commit targeting the harness — it should
  # still warn. A rebase IN THE TARGET repo still exempts (silently, no
  # message at all) from any cwd, because you cannot stop a rebase to get a
  # review; this half of the scenario is unaffected by the demotion.
  # Retiring Scenario 17 removed the incidental staged-uncovered-file it used
  # to leave behind for this scenario to inherit — stage one explicitly now.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# unreviewed, scenario 18 fixture' > "$R/adapters/claude-code/hooks/lib/scenario18.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/scenario18.sh ) >/dev/null 2>&1
  local RB="$T/rebasing"; mkdir -p "$RB"
  ( cd "$RB" && git init -q . && git config user.email t@example.com && git config user.name T ) >/dev/null 2>&1
  local rbgd; rbgd="$(cd "$RB" && git rev-parse --git-dir)"
  case "$rbgd" in /*) : ;; *) rbgd="$RB/$rbgd" ;; esac
  : > "$rbgd/REBASE_HEAD"
  runfrom_capture "$RB" "git -C $R $SUB -m x"
  rc="$RUN_RC"
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  case "$RUN_MSG" in *scenario18.sh*) pass "a FOREIGN repo's rebase does not disarm DETECTION" ;; \
    *) fail "foreign rebase state silently disarmed detection (no advisory message)"; esac
  rm -f "$rbgd/REBASE_HEAD"
  # ...and a genuine rebase IN THE TARGET still exempts SILENTLY, from any cwd
  # (distinguishing "exempted before ever checking" from "checked, warned,
  # allowed anyway" — both are rc=0 now, so the message is what proves which).
  local tgd; tgd="$(cd "$R" && git rev-parse --git-dir)"
  case "$tgd" in /*) : ;; *) tgd="$R/$tgd" ;; esac
  : > "$tgd/REBASE_HEAD"
  runfrom_capture "$RB" "git -C $R $SUB -m x"
  rc="$RUN_RC"
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  [[ -z "$RUN_MSG" ]] && pass "a rebase IN THE TARGET repo exempts SILENTLY (no advisory message at all)" \
    || fail "genuine target-repo rebase produced a message ('${RUN_MSG:0:60}...') — the exemption no longer short-circuits before detection"
  rm -f "$tgd/REBASE_HEAD"

  echo "Scenario 19: PowerShell tool input is warned on too"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# unreviewed' > "$R/adapters/claude-code/hooks/lib/admission-lib.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  local ps_payload
  ps_payload="$(jq -nc --arg c "$CV -m x" '{tool_name:"PowerShell",tool_input:{command:$c}}')"
  RUN_MSG="$(printf '%s' "$ps_payload" | ( cd "$R" && bash "$SELF" ) 2>&1 1>/dev/null)"; rc=$?
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  case "$RUN_MSG" in *admission-lib.sh*) pass "a PowerShell-tool commit is still detected/warned" ;; *) fail "PowerShell detection silently stopped"; esac
  ps_payload="$(jq -nc --arg c "Set-Location $R; $CV -m x" '{tool_name:"PowerShell",tool_input:{command:$c}}')"
  RUN_MSG="$(printf '%s' "$ps_payload" | ( cd "$OUT" && bash "$SELF" ) 2>&1 1>/dev/null)"; rc=$?
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  case "$RUN_MSG" in *admission-lib.sh*) pass "PowerShell Set-Location + commit is still detected/warned" ;; *) fail "PowerShell Set-Location detection silently stopped"; esac

  echo "Scenario 20: RETIRED — was 'the INLINE waiver from the block message must reach the override branch AND log'"
  # This scenario tested the REVIEW_RECORD_GATE_OVERRIDE inline-vs-exported
  # parsing/logging path, which no longer exists (see Scenario 8). Nothing to
  # test here any more; kept as a numbered marker for scenario-count legibility.

  echo "Scenario 21: C3 — command-position shapes must all still be DETECTED (was: BLOCK)"
  # Command position was tested as "the segment starts with the literal string
  # git". `( cd X && git <verb> )` occurs 210 times in adapters/ on this tree, and
  # work-integrity-gate.sh:1093 is literally that shape.
  while IFS='|' read -r _lbl _cwd _cmd; do
    [[ -n "$_lbl" ]] || continue
    runfrom_capture "$_cwd" "$_cmd"
    rc="$RUN_RC"
    [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc): $_lbl"
    case "$RUN_MSG" in *admission-lib.sh*) pass "DETECTS: $_lbl" ;; *) fail "FAIL-OPEN (undetected): $_lbl"; esac
  done <<EOF
subshell with cd|$OUT|( cd $R && $CV -m x )
subshell glued|$R|($CV -m x)
brace group|$OUT|{ cd $R && $CV -m x; }
if/then|$R|if true; then $CV -m x; fi
for/do|$R|for f in a; do $CV -m x; done
negation|$R|! $CV -m x
time keyword|$R|time $CV -m x
EOF
  # The backslash-newline shape cannot ride in the line-oriented table above —
  # the command itself contains a newline, which `read` would split into a
  # second, malformed row (it did, and read as a fail-open).
  runfrom_capture "$R" "git \\"$'\n'"$SUB -m x"
  rc="$RUN_RC"
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  case "$RUN_MSG" in *admission-lib.sh*) pass "DETECTS: backslash-newline line continuation" ;; \
    *) fail "FAIL-OPEN (undetected): backslash-newline line continuation"; esac

  echo "Scenario 22: M1 — the cwd-fallback must not over-fire on another repo"
  # Round 4 fell back to the cwd for EVERY unresolvable target, claiming
  # "falling back to the cwd cannot over-fire". False whenever the cwd IS the
  # harness repo — the normal case. This blocked a commit aimed elsewhere,
  # citing whatever harness file happened to be staged here.
  rc="$(runfrom "$R" "W=$T/elsewhere; git -C \"\$W\" $SUB -m x")"
  [[ "$rc" == "0" ]] && pass "commit targeting an unrelated repo is NOT blocked by our staged file" \
    || fail "OVER-FIRE (rc=$rc): blocked a commit aimed at another repo"
  # ...but a genuinely UNKNOWN target (no visible assignment) must still be
  # DETECTED (was: blocked), or the round-3 fail-open reopens undetected.
  runfrom_capture "$R" "git -C \$REPO $SUB -m x"
  rc="$RUN_RC"
  [[ "$rc" == "0" ]] || fail "advisory commit unexpectedly blocked (rc=$rc)"
  case "$RUN_MSG" in *admission-lib.sh*) pass "unresolvable \$REPO target still DETECTS (round-3 fail-open stays closed)" ;; \
    *) fail "FAIL-OPEN (undetected): unexpanded variable target"; esac

  echo "Scenario 23: review-independence RI1b — committing uncovered content"
  echo "auto-enqueues a review-queue item (docs/plans/review-independence.md)"
  if [[ -f "$_RRCG_SELF_DIR/lib/review-queue-auto-enqueue-lib.sh" ]] \
     && [[ -f "$_RRCG_SELF_DIR/../scripts/review-queue.sh" ]]; then
    local RQDIR="$T/review-queue-scenario23"
    mkdir -p "$RQDIR"
    ( cd "$R" && git reset -q ) >/dev/null 2>&1
    mkdir -p "$R/adapters/claude-code/hooks/lib"
    echo '# another unreviewed harness change, scenario 23 fixture' > "$R/adapters/claude-code/hooks/lib/ri1b-fixture.sh"
    ( cd "$R" && git add adapters/claude-code/hooks/lib/ri1b-fixture.sh ) >/dev/null 2>&1
    local payload23
    payload23="$(jq -nc --arg c 'git commit -m "feat: ri1b fixture"' '{tool_name:"Bash",tool_input:{command:$c}}')"
    RQ_AUTO_ENQUEUE_MODE=sync REVIEW_QUEUE_STATE_DIR="$RQDIR" \
      bash -c 'export RQ_AUTO_ENQUEUE_MODE REVIEW_QUEUE_STATE_DIR; printf "%s" "$1" | (cd "$2" && bash "$3") >/dev/null 2>&1' \
      _ "$payload23" "$R" "$SELF"
    if ls "$RQDIR"/rq-*.json >/dev/null 2>&1 \
       && grep -l "ri1b-fixture.sh" "$RQDIR"/rq-*.json >/dev/null 2>&1; then
      pass "auto-enqueue wrote a review-queue.sh item naming the uncovered file"
    else
      fail "auto-enqueue did NOT write a review-queue item (RI1b splice broken or removed)"
    fi
    ( cd "$R" && git reset -q ) >/dev/null 2>&1
    rm -f "$R/adapters/claude-code/hooks/lib/ri1b-fixture.sh"
  else
    fail "review-queue-auto-enqueue-lib.sh or scripts/review-queue.sh missing from this checkout — RI1b splice cannot be verified"
  fi

  rm -rf "$T"
  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    # `export HARNESS_SELFTEST=1` arms the sandbox guard in signal-ledger.sh
    # for the whole run and for every re-invocation the self-test spawns.
    # Without it this self-test wrote the operator's real
    # ~/.claude/state/signal-ledger.jsonl. PROVEN behaviorally: clean-HOME
    # probe created it without this arm, nothing under .claude/ with it.
    # (Historically also guarded _rrcg_log_override's real override-log write
    # — that function was removed 2026-07-30 along with the mechanism it
    # served; Scenario 8 below now proves the retired log path stays untouched.)
    --self-test) export HARNESS_SELFTEST=1; _rrcg_self_test; exit $? ;;
    *) _rrcg_main; exit $? ;;
  esac
fi
