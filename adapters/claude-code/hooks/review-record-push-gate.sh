#!/bin/bash
# review-record-push-gate.sh — the AUTHORITATIVE review-record coverage gate.
#
# ============================================================================
# WHY THIS EXISTS, AND WHY IT IS NOW THE AUTHORITATIVE LAYER
# ============================================================================
# review-record-commit-gate.sh (PreToolUse, commit time) was built 2026-07-29
# to close the f6562b2 gap (unreviewed harness content reaching master). It
# is enforced at a CONVENIENT layer, not the FUNNEL every path traverses
# (adapters/claude-code/doctrine/deterministic-process.md, Rule 1) — and it
# has at least four live bypass routes: REVIEW_RECORD_GATE_OVERRIDE (any
# string >=20 chars that is not a placeholder — no operator authorization
# checked), the mid-rebase/cherry-pick exemption (cherry-pick is exactly how
# this harness's own orchestrator pattern moves every builder commit onto the
# integration branch), --amend, and rebase. Worse: it is UNSATISFIABLE from
# the layer it fires at. Measured 2026-07-30 (docs/backlog.md
# REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01): of 78 override events in
# ~/.claude/state/review-record-gate-overrides.log, every one of the 10 from
# today states the same reason — a builder subagent has no Task/Agent-
# dispatch tool and cannot itself invoke harness-reviewer, so the gate's own
# prescribed remedy is unreachable from the actor it fires on. The only two
# exits were "never commit" or "override" — a remedy-chain deadlock (ADR 059
# D5 class), not agent misconduct.
#
# This gate moves enforcement to git push — the funnel every LOCAL commit
# crosses to reach the shared remote, regardless of how it got onto the local
# branch (authored directly, cherry-picked, rebased, amended, or committed
# under a commit-time override). It is NOT a funnel for content that reaches
# master by a route bypassing a local `git push` on a machine running this
# harness at all — see this gate's own manifest.json bypass_paths entry for
# the three routes that do not cross it (--no-verify, a GitHub web-UI/API
# merge, an unconfigured machine). It is ALSO the right layer on remedy-reachability
# grounds, not just funnel grounds: the actor at push time is the
# ORCHESTRATOR (scripts/estate-merge.sh's real `git push`, or an operator's
# own push), which DOES have Task/Agent-dispatch capability — so the
# prescribed remedy (dispatch harness-reviewer, record the verdict) is
# reachable from the layer that enforces it. Enforcement belongs where the
# required action is possible; review-record-commit-gate.sh is demoted to
# ADVISORY (warns, never blocks) for exactly this reason — see its own
# header.
#
# GOLDEN SCENARIO — REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01 (docs/
# backlog.md, landed e91cdfa): a builder subagent with NO Task/Agent-dispatch
# tool stages+commits an uncovered in-surface file. It must be able to make
# FORWARD PROGRESS (commit succeeds, advisory warning only) WITHOUT setting
# any override — while the SAME uncovered content must still be REFUSED at
# push time, because nothing downstream of the builder's own session
# reviewed it yet. The two halves are asserted in two files, not one
# end-to-end scenario: review-record-commit-gate.sh's self-test Scenario 1b
# ("GOLDEN — REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01") proves forward
# progress with no override; Scenario 1 below proves the same shape of
# content is still refused at push.
#
# ============================================================================
# HOW COVERAGE IS CHECKED (reuses hooks/lib/review-record-gate-lib.sh; this
# file does NOT reimplement rrg_in_surface / rrg_is_covered)
# ============================================================================
# For every ref-update line on stdin (git's pre-push protocol: `<local-ref>
# <local-sha> <remote-ref> <remote-sha>`) whose remote-ref is refs/heads/
# master or refs/heads/main:
#   1. Skip delete-pushes (local-sha all zeros).
#   2. Compute the range of commits being introduced (remote-sha..local-sha,
#      or — for a first push of the branch — the oldest commit not already
#      on any remote, same proven logic as pre-push-scan.sh).
#   3. `git diff --name-only --diff-filter=ACMR` over that range — the set of
#      paths whose content differs (excludes pure deletions, same exemption
#      review-record-commit-gate.sh uses; a removed blob has nothing to
#      review).
#   4. For every path rrg_in_surface flags, resolve its blob AT local-sha
#      (rrg_blob_sha_of_ref) — the bytes that will actually land on the
#      remote, NOT the working tree, NOT any intermediate commit in the
#      range. This is what makes the "stage evil, restore worktree to a
#      covered blob" trick review-record-commit-gate.sh's own Scenario 11
#      closed at commit time IRRELEVANT here: whatever a rebase/cherry-pick/
#      amend produces, the gate reads the committed object graph, not any
#      working tree.
#   5. rrg_is_covered against grandfather-manifest.json / index.json AS OF
#      local-sha (ref-based read — a review record committed earlier in the
#      SAME push is honored, same one-pass-fixable property the commit gate
#      has).
#   6. Uncovered + no valid override marker (see below) -> BLOCK the entire
#      push (git pre-push semantics: a nonzero exit aborts every ref update
#      in the invocation, not just the offending one).
#
# A blob that fails to resolve at local-sha for an ACMR-flagged path (should
# not happen given the diff-filter, but "bailouts resolve toward block" is
# this codebase's own hard-won principle — review-record-commit-gate.sh's
# _rrcg_record_is_staged comment) is treated as UNCOVERED, not skipped.
#
# Infra-missing (no git, no jq) fails OPEN — never brick a machine that
# cannot even run the check. This is a DIFFERENT case from "git/jq present
# but this content genuinely isn't covered", which BLOCKS.
#
# ============================================================================
# THE OVERRIDE: AN AUTHORIZATION, NOT A SENTENCE (Rule 2)
# ============================================================================
# REVIEW_RECORD_GATE_OVERRIDE (the commit-time gate's escape hatch) is NOT
# honored here — an inline env var an agent can set in the same command it
# is authorizing is not an authorization at the layer where enforcement is
# real (deterministic-process.md Rule 2). The only escape hatch this gate
# recognizes is a MARKER FILE written by a SEPARATE prior invocation of
# scripts/authorize-review-record-push-override.sh — same shape as
# /grant-local-edit (session-scoped, operator-authorized, time-boxed marker
# under ~/.claude/state/, consumed by the gate). The marker is additionally
# SHA-SCOPED (review-record-push-override-<sha>-<timestamp>.txt): it
# authorizes exactly the commit it names, not a time window in which any
# push rides free — closing the "unrelated push reuses someone else's
# emergency window" gap a bare time-boxed marker would leave open.
#
# Trust model is IDENTICAL to /grant-local-edit's own documented one (its
# SKILL.md: "the marker has no further authorization mechanism beyond mtime +
# slug-match; the trust model is operator controls ~/.claude/state/"): this
# is not a claim of cryptographic non-forgeability, it is a SEPARATE-STEP,
# SHA-SCOPED, TIME-BOXED, reason-validated artifact, meaningfully harder to
# produce by accident or inline than an env var — not an unbypassable one.
#
# ============================================================================
# THE PROOF OBLIGATION (deterministic-process.md)
# ============================================================================
#   CHOKEPOINT      : pre-push (git-hooks/pre-push dispatcher, wired via
#                      `git config --global core.hooksPath`; fires on every
#                      `git push` to refs/heads/master|main from any repo on
#                      this machine that has this harness installed).
#   BYPASS_PATHS    : see manifest.json's review-record-push-gate entry for
#                      the full enumeration; summary: `git push --no-verify`
#                      (git-native, NAMED-AND-ACCEPTED, no server-side check
#                      exists yet), a GitHub web-UI/API merge or any push
#                      from a machine without core.hooksPath configured to
#                      this harness (NAMED-AND-ACCEPTED, local-hook-only
#                      enforcement — a server-side required-status-check is
#                      the definitive close and is not built here), and
#                      `core.hooksPath` unset/overridden per-repo
#                      (NAMED-AND-ACCEPTED). The override-marker abuse paths
#                      (reuse for an unrelated push, replay after expiry,
#                      hand-crafted invalid-reason marker) are CLOSED by the
#                      sha-scoping + TTL + reason re-validation below.
#
# Self-test: bash review-record-push-gate.sh --self-test

set -u

_RRPG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

ZERO_SHA="0000000000000000000000000000000000000000"
EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
STABLE_BRANCHES_REGEX='^refs/heads/(master|main)$'
RRPG_OVERRIDE_TTL_SECONDS="${RRPG_OVERRIDE_TTL_SECONDS:-900}"   # 15 min — a
# push is a one-shot action, not a sustained editing session, so this is
# tighter than /grant-local-edit's 30-minute window by design.

# ------------------------------------------------------------
# Sandboxed state (HARNESS_SELFTEST=1 never touches the operator's real
# ~/.claude/state/ — same proven pattern as review-record-commit-gate.sh's
# _rrcg_log_override, added after a clean-HOME probe proved a self-test
# without this wrote real operator files).
# ------------------------------------------------------------

_rrpg_state_dir() {
  if [[ -n "${REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR:-}" ]]; then
    printf '%s' "$REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR"
  elif [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s' "${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}/review-record-push-gate-selftest/$$}/state"
  else
    printf '%s' "$HOME/.claude/state"
  fi
}

_rrpg_log_override() {
  local sha="$1" reason="$2" repo="$3"
  local log="${REVIEW_RECORD_PUSH_GATE_LOG:-}"
  if [[ -z "$log" ]]; then
    if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
      log="${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}/review-record-push-gate-selftest/$$}/review-record-push-gate-overrides.log"
    else
      log="$HOME/.claude/state/review-record-push-gate-overrides.log"
    fi
  fi
  mkdir -p "$(dirname "$log")" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
    "${repo:-unknown}" "$sha" "$reason" >> "$log" 2>/dev/null || true
}

# _rrpg_infra_warn <what-was-missing> -- the LOUD half of an infrastructure
# fail-open (harness-reviewer C3). The gate still allows the push (a missing
# binary must not brick a machine), but never silently: the operator sees, in
# plain words, that this push was NOT checked. Deliberately worded as a
# statement of fact about THIS push rather than a generic "warning: jq
# missing", because the thing that matters is the review status of the bytes
# now heading for the remote, not the tooling trivia that caused it.
_rrpg_infra_warn() {
  local why="$1"
  {
    echo "================================================================"
    echo "REVIEW-RECORD PUSH GATE — COULD NOT RUN; THIS PUSH WAS *NOT* CHECKED"
    echo "================================================================"
    echo "Reason: ${why}."
    echo
    echo "Unreviewed harness content may be reaching the remote right now."
    echo "This is a FAIL-OPEN (a missing tool must not brick your ability to"
    echo "push), not a pass — nothing about review coverage was verified."
    echo
    echo "If you did not expect this, stop and check the push:"
    echo "  bash adapters/claude-code/hooks/review-record-push-gate.sh --self-test"
    echo "================================================================"
  } >&2
}

_rrpg_mtime_epoch() {
  local f="$1"
  [[ -f "$f" ]] || { echo 0; return; }
  stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0
}

# _rrpg_fresh_override <sha> -- echoes the validated reason on stdout + rc 0
# if a fresh, SHA-matching, reason-valid marker exists; rc 1 otherwise. Every
# guard is re-checked HERE (not trusted from write time): freshness (mtime),
# sha-match (glob on the exact commit), and reason validity (re-run through
# rrg_validate_waiver_reason) — a hand-crafted or stale marker must not work.
_rrpg_fresh_override() {
  local sha="$1" dir; dir="$(_rrpg_state_dir)"
  [[ -d "$dir" ]] || return 1
  local now; now=$(date +%s)
  local marker
  for marker in "$dir/review-record-push-override-${sha}-"*.txt; do
    [[ -f "$marker" ]] || continue
    local mtime age
    mtime=$(_rrpg_mtime_epoch "$marker")
    age=$(( now - mtime ))
    [[ "$age" -ge 0 && "$age" -le "$RRPG_OVERRIDE_TTL_SECONDS" ]] || continue
    local reason
    reason="$(grep '^Reason: ' "$marker" 2>/dev/null | head -1 | sed 's/^Reason: //')"
    command -v rrg_validate_waiver_reason >/dev/null 2>&1 || continue
    rrg_validate_waiver_reason "$reason" || continue
    printf '%s' "$reason"
    return 0
  done
  return 1
}

# ------------------------------------------------------------
# Range resolution — same proven logic as pre-push-scan.sh (PROVEN over the
# 2026-05 credential-scanner rollout; not reimplemented from scratch here).
# ------------------------------------------------------------

_rrpg_range() {
  local local_sha="$1" remote_sha="$2"
  if [[ "$remote_sha" == "$ZERO_SHA" ]]; then
    local oldest
    oldest="$(git rev-list "$local_sha" --not --remotes 2>/dev/null | tail -1)"
    if [[ -n "$oldest" ]]; then
      if git rev-parse --verify "${oldest}^" >/dev/null 2>&1; then
        printf '%s^..%s' "$oldest" "$local_sha"
      else
        printf '%s..%s' "$EMPTY_TREE" "$local_sha"
      fi
    else
      printf '%s..%s' "$EMPTY_TREE" "$local_sha"
    fi
  else
    printf '%s..%s' "$remote_sha" "$local_sha"
  fi
}

_rrpg_block_message() {
  local repo_root="$1" remote_ref="$2" sha="$3" degraded="$4"; shift 4
  local -a files=("$@")
  {
    echo "================================================================"
    echo "REVIEW-RECORD PUSH GATE — PUSH BLOCKED (authoritative gate)"
    echo "================================================================"
    echo
    if [[ "$degraded" == "1" ]]; then
      echo "NOTE: could not compute the exact pushed range (the remote-tracked"
      echo "sha was unresolvable locally) — scanned the ENTIRE tree at $sha"
      echo "instead. Some files listed below may already be on the remote from"
      echo "an earlier push; try \`git fetch\` first if this looks wrong."
      echo
    fi
    echo "Pushing $remote_ref at $sha would land UNREVIEWED harness content on"
    echo "the remote:"
    local f
    for f in "${files[@]}"; do echo "  • $f"; done
    echo
    echo "This is the AUTHORITATIVE review-record gate (adapters/claude-code/"
    echo "doctrine/deterministic-process.md). review-record-commit-gate.sh is"
    echo "advisory only now — it warns at commit time but does not block,"
    echo "because a builder subagent typically has no Task/Agent-dispatch tool"
    echo "and cannot itself invoke harness-reviewer (docs/backlog.md"
    echo "REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01). The orchestrator DOES"
    echo "have dispatch capability and is the actor at push time — enforcement"
    echo "belongs where the required action is possible."
    echo
    echo "TO PROCEED, ONE of:"
    echo
    echo "  1. Get the content reviewed through the SANCTIONED, INDEPENDENT"
    echo "     pathway (review-before-deploy.md: review-queue.sh -> review-"
    echo "     runner.sh is \"the author's only legal move\" -- writing +"
    echo "     committing a PASS record yourself, even a genuine one, makes"
    echo "     the record's author == the content's author, which harness-"
    echo "     doctor's review-reviewer-independence check REDs on post-cutover):"
    echo "       bash adapters/claude-code/scripts/review-queue.sh list --status queued"
    echo "       bash adapters/claude-code/scripts/review-runner.sh claim --item-id <id> --repo-root ."
    echo "       (dispatch harness-reviewer against the claimed item, then)"
    echo "       bash adapters/claude-code/scripts/review-runner.sh finalize \\"
    echo "         --item-id <id> --repo-root . --verdict PASS \\"
    echo "         --quote '<verdict sentence>' --plan-ref <plan>"
    echo "     (finalize WRITES AND COMMITS the record under the reviewer's own"
    echo "     git identity -- a SEPARATE Bash call from the push, NL-FINDING-016)"
    echo "     If no queue item exists yet for these files, review-record-"
    echo "     commit-gate.sh's RI1b splice enqueues one automatically the next"
    echo "     time this content is committed; or file one by hand:"
    echo "       bash adapters/claude-code/scripts/review-queue.sh enqueue \\"
    echo "         --branch <branch> \\"
    for f in "${files[@]}"; do echo "         --file $f --blob-sha <blob-sha-of-$f-at-$sha> \\"; done
    echo "         --repo-root ."
    echo
    echo "  2. Genuine operator-authorized emergency override — requires a"
    echo "     SEPARATE prior step; an inline env var is NOT sufficient at"
    echo "     this authoritative layer (deterministic-process.md Rule 2):"
    echo
    echo "       bash adapters/claude-code/scripts/authorize-review-record-push-override.sh \\"
    echo "         \"why this cannot wait for review\" --sha $sha"
    echo
    echo "     Then retry the push. The marker authorizes ONLY this exact"
    echo "     commit ($sha) and expires in ${RRPG_OVERRIDE_TTL_SECONDS}s."
    echo
    echo "Emergency bypass of ALL local hooks (NOT recommended — unreviewed"
    echo "content WILL reach the remote): git push --no-verify"
    echo "================================================================"
  } >&2
}

# ------------------------------------------------------------
# Identity + disarm messages (harness-reviewer CRITICAL 1 / MAJOR 3)
# ------------------------------------------------------------

# _rrpg_is_harness_repo_inline <repo_root> -- the SAME anchor order as
# rrg_harness_identity, reimplemented inline so it still works when the lib
# itself is missing or truncated. Deliberate duplication: the whole point is to
# survive deletion of the file that would otherwise answer this question.
_rrpg_is_harness_repo_inline() {
  local repo_root="$1" mp="adapters/claude-code/manifest.json" r b
  if command -v git >/dev/null 2>&1 \
     && git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$repo_root" cat-file -e "HEAD:${mp}" 2>/dev/null && return 0
    for r in $(git -C "$repo_root" remote 2>/dev/null); do
      for b in master main; do
        git -C "$repo_root" cat-file -e "refs/remotes/${r}/${b}:${mp}" 2>/dev/null && return 0
      done
    done
  fi
  [[ -f "$repo_root/$mp" ]]
}

# _rrpg_missing_lib_block <repo_root> <lib_path> [detail]
_rrpg_missing_lib_block() {
  local repo_root="$1" lib="$2" detail="${3:-could not be sourced}"
  {
    echo "================================================================"
    echo "REVIEW-RECORD PUSH GATE — PUSH BLOCKED (gate library missing)"
    echo "================================================================"
    echo "This repo IS the harness repo, but the gate's own coverage library"
    echo "$detail:"
    echo "  $lib"
    echo
    echo "The library is REPO CONTENT, not a system binary. A missing jq is a"
    echo "machine problem and fails open (loudly); a missing library is the"
    echo "harness repo disarming its own gate, which is the cheapest bypass"
    echo "there is. Refusing the push instead."
    echo
    echo "Restore it and push again:"
    echo "  git checkout master -- adapters/claude-code/hooks/lib/review-record-gate-lib.sh"
    echo "================================================================"
  } >&2
}

# _rrpg_identity_removal_block <repo_root> <remote_ref> <local_sha> <anchor>
# The manifest exists at the remote-side anchor but NOT in the pushed commit:
# this push REMOVES the file that three separate controls use to decide whether
# they apply. Loud by construction (harness-reviewer MAJOR 3 — the scope test
# was the one silent, pusher-reachable fail-open C3's loudness sweep missed).
_rrpg_identity_removal_block() {
  local repo_root="$1" remote_ref="$2" sha="$3" anchor="$4"
  {
    echo "================================================================"
    echo "REVIEW-RECORD PUSH GATE — PUSH BLOCKED (gate identity removal)"
    echo "================================================================"
    echo "Pushing $remote_ref at $sha would DELETE"
    echo "  adapters/claude-code/manifest.json"
    echo "which is present at the remote-side anchor ($anchor)."
    echo
    echo "That single deletion disarms THREE controls at once:"
    echo "  1. this gate's scope test (it would exit silently, rc=0)"
    echo "  2. the bootstrap fail-open's harness-repo scoping (C2-B re-opens)"
    echo "  3. git-hooks/pre-push's missing-gate block (demoted to a WARNING)"
    echo
    echo "Identity is therefore resolved from the state already ON THE REMOTE,"
    echo "not from the working tree the push can rewrite, and removing the"
    echo "anchor is treated as UNCOVERED rather than out-of-scope."
    echo
    echo "If this deletion is genuinely intended, it needs the same operator"
    echo "authorization as any other unreviewed harness change:"
    echo "  bash adapters/claude-code/scripts/authorize-review-record-push-override.sh \\"
    echo "    \"why the harness manifest is being removed\" --sha $sha"
    echo "================================================================"
  } >&2
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

_rrpg_main() {
  local remote="${1:-}"
  local stdin_buf; stdin_buf="$(cat 2>/dev/null || true)"
  [[ -n "$stdin_buf" ]] || return 0
  [[ -n "$remote" ]] || return 0   # no remote name -> not our path

  # ------------------------------------------------------------
  # INFRA FAIL-OPENS ARE LOUD (harness-reviewer C3, 2026-07-30).
  #
  # These three arms previously returned 0 with ZERO bytes of stderr. PROVEN:
  # with a shim PATH carrying git/grep/sed but NOT jq, the gate returned rc=0
  # silently -- so `PATH=<no-jq> git push` was a ONE-TOKEN INLINE PREFIX that
  # defeated the authoritative review gate without a trace. That is precisely
  # the shape this file's own header (Rule 2, above) declares is NOT a
  # legitimate override: an inline env var the agent sets in the same command
  # it is authorizing. They still fail OPEN -- a missing binary must never
  # brick a machine's ability to push -- but they now SAY SO, so a defeated
  # gate is visible in the push output instead of indistinguishable from a
  # clean pass.
  #
  # ORDERING IS DELIBERATE: the "is this the harness repo?" test runs BEFORE
  # the jq/lib arms, so a machine without jq pushing from an unrelated repo
  # gets silence (correct -- this gate has no business there) while the SAME
  # machine pushing the harness repo gets the warning. Making the jq arm loud
  # ahead of the scope test would spam every push from every repo on the box,
  # which is the trust-erosion shape that turns a real warning into noise
  # people learn to scroll past.
  # ------------------------------------------------------------
  if ! command -v git >/dev/null 2>&1; then
    _rrpg_infra_warn "git is not on PATH, so the pushed range cannot be computed"
    return 0
  fi

  local repo_root
  if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$repo_root" ]]; then
    _rrpg_infra_warn "the repository root could not be resolved (\`git rev-parse --show-toplevel\` failed)"
    return 0
  fi

  # ------------------------------------------------------------
  # SCOPE TEST — the gate's FIRST decision, and formerly its most silent
  # fail-open (harness-reviewer CRITICAL 1 + MAJOR 3, 2026-07-30).
  #
  # This was `[[ -f "$repo_root/adapters/claude-code/manifest.json" ]] ||
  # return 0`: a single working-tree read, inside the pusher's write set, that
  # ran BEFORE the three loud infra arms. PROVEN against a real bare remote:
  # harness repo + `git rm -f adapters/claude-code/manifest.json` in the same
  # push as an unreviewed hook => rc=0, ZERO bytes of stderr, unreviewed file
  # on the remote. So C3's stated invariant ("a defeated gate is never
  # indistinguishable from a passing one") did not hold for the gate's very
  # first decision, and the escape cost one command.
  #
  # The scope test is now anchored on state the push CANNOT rewrite (see
  # rrg_harness_identity in lib/: remote_sha, then the remote-tracking ref,
  # then HEAD, then -- last -- the working tree). Sourcing the lib therefore
  # has to happen BEFORE the scope test rather than after it, which reorders
  # the jq/lib arms relative to the scope test. That reordering is safe for the
  # trust-erosion budget C3 was protecting: BOTH arms below stay silent unless
  # this repo is the harness repo, so an unrelated repo on a jq-less machine
  # still gets silence, exactly as before.
  # ------------------------------------------------------------
  local _rrpg_lib="$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh"
  # shellcheck source=/dev/null
  if ! source "$_rrpg_lib" 2>/dev/null; then
    # The lib is REPO CONTENT, not a system binary -- deleting it is the same
    # "the enforcing bytes are mutable" class as M8, not the "this machine is
    # missing jq" class. PROVEN: `git rm` of the lib alone took this gate to
    # rc=0 and landed the deletion on the remote. Decide scope WITHOUT the lib
    # (inline, same anchor order) so a harness repo cannot disarm the gate by
    # deleting the gate's own library.
    if _rrpg_is_harness_repo_inline "$repo_root"; then
      _rrpg_missing_lib_block "$repo_root" "$_rrpg_lib"
      return 1
    fi
    return 0
  fi
  local _fn
  for _fn in rrg_harness_identity rrg_remote_tracking_refs; do
    if ! command -v "$_fn" >/dev/null 2>&1; then
      if _rrpg_is_harness_repo_inline "$repo_root"; then
        _rrpg_missing_lib_block "$repo_root" "$_rrpg_lib"
        return 1
      fi
      return 0
    fi
  done

  # Collect every anchor this push offers, from the stdin ref lines, BEFORE
  # deciding scope: remote_sha for each pushed ref, plus the remote-tracking
  # refs for the same branches.
  local -a _anchors=()
  local _lr _ls _rr _rs _t
  while IFS=' ' read -r _lr _ls _rr _rs; do
    [[ -n "$_rr" ]] || continue
    [[ -n "$_rs" ]] && _anchors+=("$_rs")
    while IFS= read -r _t; do
      [[ -n "$_t" ]] && _anchors+=("$_t")
    done < <(rrg_remote_tracking_refs "$repo_root" "$_rr" 2>/dev/null)
  done <<< "$stdin_buf"

  # Scope limit, NOT a fail-open: this gate only governs the harness repo.
  # Silence here is correct for a genuinely foreign repo and must stay silent.
  rrg_harness_identity "$repo_root" "${_anchors[@]+"${_anchors[@]}"}" >/dev/null 2>&1 || return 0

  if ! command -v jq >/dev/null 2>&1; then
    _rrpg_infra_warn "jq is not on PATH, so review coverage cannot be read"
    return 0
  fi
  # Past the scope test, this IS the harness repo, so a lib that sourced but is
  # missing a function it must define is a TRUNCATED/EDITED lib -- repo content
  # again, not a missing binary. Block rather than warn-and-allow, for the same
  # reason as the source failure above.
  for _fn in rrg_in_surface rrg_is_covered rrg_blob_sha_of_ref rrg_validate_waiver_reason; do
    if ! command -v "$_fn" >/dev/null 2>&1; then
      _rrpg_missing_lib_block "$repo_root" "$_rrpg_lib" "sourced but does not define ${_fn}()"
      return 1
    fi
  done

  # review-independence RI1b (docs/plans/review-independence.md) is NOT
  # spliced in here, unlike review-record-commit-gate.sh. harness-reviewer
  # PROVEN 2026-07-30: rq_auto_enqueue_uncovered reads `git diff --cached`
  # (the INDEX) -- correct at commit time, but at push time the index
  # normally equals HEAD, so the call would be wired but permanently inert
  # (a Rule 3 violation: a step that runs and enqueues nothing is not part
  # of the process). Calling it anyway to look complete, when it structurally
  # cannot fire from this caller, would be worse than the honest gap this
  # comment states: a RANGE-aware auto-enqueue entry point (taking the
  # `uncovered` array this gate already computes below, rather than
  # re-deriving it from the index) is the correct fix and is not yet built.
  # Tracked as a follow-up, not silently dropped.

  local saw_block=0
  local local_ref local_sha remote_ref remote_sha
  while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
    [[ -n "$remote_ref" ]] || continue
    printf '%s' "$remote_ref" | grep -qE "$STABLE_BRANCHES_REGEX" || continue
    [[ "$local_sha" == "$ZERO_SHA" ]] && continue   # delete-push, nothing to review

    # ------------------------------------------------------------
    # IDENTITY REMOVAL (harness-reviewer CRITICAL 1). Checked per-ref and
    # BEFORE the range diff, so it fires even when the manifest was removed in
    # some earlier commit that this range does not span. "Present at the
    # remote-side anchor but absent in the pushed commit" is UNCOVERED-and-
    # BLOCK, never out-of-scope.
    # ------------------------------------------------------------
    local _id_anchor
    if _id_anchor="$(rrg_harness_identity "$repo_root" "$remote_sha" \
                       $(rrg_remote_tracking_refs "$repo_root" "$remote_ref" 2>/dev/null) 2>/dev/null)" \
       && [[ -n "$_id_anchor" && "$_id_anchor" != "working-tree" ]] \
       && ! git -C "$repo_root" cat-file -e "${local_sha}:${RRG_MANIFEST_RELPATH}" 2>/dev/null; then
      saw_block=1
      _rrpg_identity_removal_block "$repo_root" "$remote_ref" "$local_sha" "$_id_anchor"
      continue
    fi

    local range files deleted diff_rc range_degraded=0
    range="$(_rrpg_range "$local_sha" "$remote_sha")"
    files="$(git -C "$repo_root" diff --name-only --diff-filter=ACMR "$range" 2>/dev/null)"
    diff_rc=$?
    # DELETIONS ARE PART OF THE SUBJECT SET (harness-reviewer CRITICAL 3).
    # --diff-filter=ACMR excludes D, so `git rm hooks/victim-gate.sh` was a
    # rc=0 no-op: deleting a gate was invisible to the gate. Enumerated
    # separately because a deleted path has no blob at local_sha, so it can
    # never take the ordinary coverage path.
    deleted="$(git -C "$repo_root" diff --name-only --diff-filter=D "$range" 2>/dev/null)"
    if [[ "$diff_rc" -ne 0 ]]; then
      range_degraded=1
      # BAILOUT RESOLVES TOWARD BLOCK (this file's own stated principle,
      # applied one line earlier than the blob-resolution case below): a
      # `git diff` failure (e.g. remote_sha unresolvable locally -- PROVEN
      # reachable on both a plain push and a --force push when the local
      # object store lacks remote_sha) is "cannot compute the pushed range",
      # NOT "nothing changed". Silently continuing here previously scored a
      # computation error as a clean, empty subject set -- the review-record-
      # commit-gate.sh Scenario 11 class of hole (blob resolution), one layer
      # up (range resolution). Retry against the maximally strict range
      # (empty-tree..local_sha, the SAME fallback _rrpg_range already uses for
      # a genuine first push) so a transient/unresolvable remote_sha degrades
      # to "scan everything in the pushed tree" rather than "scan nothing".
      files="$(git -C "$repo_root" diff --name-only --diff-filter=ACMR "${EMPTY_TREE}..${local_sha}" 2>/dev/null)"
      diff_rc=$?
      if [[ "$diff_rc" -ne 0 ]]; then
        # Even the empty-tree diff failed (should not happen against a real
        # commit) -- genuinely cannot verify. Block rather than guess.
        saw_block=1
        {
          echo "================================================================"
          echo "REVIEW-RECORD PUSH GATE — PUSH BLOCKED (cannot verify)"
          echo "================================================================"
          echo "Could not compute the set of files changed by this push (range"
          echo "'$range' failed to diff, and the empty-tree fallback also failed)."
          echo "Refusing to push rather than silently skipping the review check."
          echo "================================================================"
        } >&2
        continue
      fi
    fi
    [[ -n "$files" ]] || [[ -n "$deleted" ]] || continue

    local -a uncovered=()
    local f sha
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      rrg_in_surface "$f" || continue
      sha="$(rrg_blob_sha_of_ref "$repo_root" "$local_sha" "$f" 2>/dev/null)" || sha=""
      if [[ -z "$sha" ]]; then
        # Bailouts resolve toward block (review-record-commit-gate.sh's own
        # hard-won principle): an unresolvable blob for a path the diff says
        # changed is "cannot verify", not "assume fine".
        uncovered+=("$f (blob unresolvable at $local_sha)")
        continue
      fi
      rrg_is_covered "$repo_root" "$local_sha" "$f" "$sha" || uncovered+=("$f")
    done <<< "$files"

    # In-surface DELETIONS. A removed path has no blob at local_sha, so
    # rrg_is_covered can never return true for it -- a deletion is UNCOVERED by
    # construction and the operator override is its only route. MEASURED cost
    # before choosing this (git log --diff-filter=D over master, 2026-07-30):
    # 8 of 1763 commits (0.45%) delete an in-surface file, 104 files all time,
    # concentrated in a few deliberate sweeps. That is the real false-positive
    # bill for making "delete the gate" as hard as "edit the gate".
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      rrg_in_surface "$f" || continue
      uncovered+=("$f (DELETED by this push — removing an in-surface file needs the same authorization as changing it)")
    done <<< "$deleted"

    [[ "${#uncovered[@]}" -eq 0 ]] && continue

    local ovr
    if ovr="$(_rrpg_fresh_override "$local_sha")" && [[ -n "$ovr" ]]; then
      _rrpg_log_override "$local_sha" "$ovr" "$repo_root"
      echo "review-record-push-gate: OVERRIDDEN for $local_sha — \"$ovr\" (logged for audit)" >&2
      continue
    fi

    saw_block=1
    _rrpg_block_message "$repo_root" "$remote_ref" "$local_sha" "$range_degraded" "${uncovered[@]}"
  done <<< "$stdin_buf"

  [[ "$saw_block" -eq 1 ]] && return 1
  return 0
}

# ===========================================================================
# Self-test
# ===========================================================================
_rrpg_self_test() {
  local PASS=0 FAIL=0
  pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
  fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }

  local T; T="$(mktemp -d)" || { echo "cannot mktemp"; return 1; }
  local SELF="$_RRPG_SELF_DIR/$(basename "${BASH_SOURCE[0]}")"
  export HARNESS_SELFTEST_DIR="$T/hs"

  # ---- fixture repo, harness-shaped (manifest.json + empty coverage files) ----
  local R="$T/repo"
  mkdir -p "$R/adapters/claude-code/hooks/lib" "$R/docs/reviews/records"
  printf '{"schema_version":1,"entries":[]}\n' > "$R/adapters/claude-code/manifest.json"
  ( cd "$R" && git init -q . && git config user.email t@example.com && git config user.name T \
      && git config core.hooksPath "" ) >/dev/null 2>&1
  cp "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" "$R/adapters/claude-code/hooks/lib/" 2>/dev/null
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/index.json"
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/grandfather-manifest.json"
  ( cd "$R" && git add -A && git commit -qm "base (no in-surface content)" ) >/dev/null 2>&1
  local BASE_SHA; BASE_SHA="$(cd "$R" && git rev-parse HEAD)"
  # ORIG_BASE_SHA is pinned once and never reassigned — later scenarios
  # reassign the mutable $BASE_SHA as their own baseline drifts forward, but
  # scenario 15 (mutation-proof) deliberately re-uses the ORIGINAL pairing
  # with $S1_SHA so its diff range is unambiguous rather than relying on
  # incidental two-tree-diff behavior across unrelated sibling commits.
  local ORIG_BASE_SHA="$BASE_SHA"

  run() { # $1=remote-name $2="local_ref local_sha remote_ref remote_sha"; echoes rc
    printf '%s\n' "$2" | ( cd "$R" && bash "$SELF" "$1" ) >/dev/null 2>&1
    echo $?
  }
  run_capture() { # same, but echoes stderr
    printf '%s\n' "$2" | ( cd "$R" && bash "$SELF" "$1" ) 2>&1 >/dev/null
  }

  echo "Scenario 1: GOLDEN CASE — uncovered in-surface content BLOCKS the push"
  echo '# unreviewed harness change' > "$R/adapters/claude-code/hooks/lib/admission-lib.sh"
  ( cd "$R" && git add -A && git commit -qm "feat: admission lib" ) >/dev/null 2>&1
  local S1_SHA; S1_SHA="$(cd "$R" && git rev-parse HEAD)"
  local rc; rc="$(run origin "refs/heads/master $S1_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "1" ]] && pass "uncovered push BLOCKED (rc=1)" || fail "expected rc 1, got $rc — the authoritative gate does not fire"
  local msg; msg="$(run_capture origin "refs/heads/master $S1_SHA refs/heads/master $BASE_SHA")"
  case "$msg" in *admission-lib.sh*) pass "message names the offending file" ;; *) fail "message omits the file" ;; esac
  case "$msg" in *authorize-review-record-push-override.sh*) pass "message names the exact authorize command" ;; *) fail "message omits the authorize command" ;; esac
  # harness-reviewer PROVEN (round 3): review-queue.sh only ever WRITES
  # status queued|claimed|completed|stale (never "pending"), and its own
  # `list` subcommand does not validate an unknown --status value -- it
  # silently returns an empty result (rc=0) instead of erroring. A remedy
  # command quoting the wrong status would look correct and always report
  # "no item" on every single block. Pin the real value.
  case "$msg" in *"review-queue.sh list --status queued"*) pass "remedy queries the queue with a status value the queue actually writes" ;; \
    *) fail "remedy queries review-queue.sh with a status it never writes (silently returns nothing, every time)"; esac
  case "$msg" in *"review-runner.sh claim"*"review-runner.sh finalize"*) pass "remedy routes through the sanctioned claim/finalize pathway, not a self-authored record" ;; \
    *) fail "remedy no longer names the sanctioned review-runner.sh pathway"; esac

  echo "Scenario 2: PASS — a PASS record (index.json) committed alongside the change allows the push"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  echo '# reviewed change' > "$R/adapters/claude-code/hooks/lib/covered.sh"
  local cov_blob; cov_blob="$(cd "$R" && git hash-object adapters/claude-code/hooks/lib/covered.sh)"
  printf '{"entries":[{"path":"adapters/claude-code/hooks/lib/covered.sh","blob_sha":"%s","kind":"harness-change-review","verdict":"PASS"}]}\n' "$cov_blob" \
    > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add -A && git commit -qm "feat: reviewed change" ) >/dev/null 2>&1
  local S2_SHA; S2_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S2_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "0" ]] && pass "PASS-covered push ALLOWED (rc=0)" || fail "blocked despite an in-index PASS record (rc=$rc)"
  ( cd "$R" && git reset -q --hard "$BASE_SHA"; git checkout -q -B master "$BASE_SHA" ) >/dev/null 2>&1
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add -A && git commit -qm "reset index" ) >/dev/null 2>&1
  BASE_SHA="$(cd "$R" && git rev-parse HEAD)"

  echo "Scenario 3: PASS — genuinely pre-cutover content allows the push"
  # MODELLED AS REAL GRANDFATHERING (rewritten 2026-07-30, harness-reviewer
  # C2-A). The previous version of this scenario committed the content AND a
  # grandfather row naming it in the SAME commit -- which is not
  # grandfathering, it is precisely the self-authored-coverage BYPASS the
  # cutover_ref binding now closes. It passed for the wrong reason, and it
  # would have stayed green through the entire vulnerability. Real
  # grandfathering means the blob EXISTED at the recorded cutover point:
  # commit the content first, record THAT commit as cutover_ref, then push a
  # range that spans it.
  echo '# pre-cutover content' > "$R/adapters/claude-code/hooks/lib/legacy.sh"
  ( cd "$R" && git add -A && git commit -qm "pre-cutover: legacy content" ) >/dev/null 2>&1
  local CUTOVER_SHA; CUTOVER_SHA="$(cd "$R" && git rev-parse HEAD)"
  local leg_blob; leg_blob="$(cd "$R" && git rev-parse "HEAD:adapters/claude-code/hooks/lib/legacy.sh")"
  printf '{"cutover_ref":"%s","entries":[{"path":"adapters/claude-code/hooks/lib/legacy.sh","blob_sha":"%s"}]}\n' \
    "$CUTOVER_SHA" "$leg_blob" > "$R/docs/reviews/records/grandfather-manifest.json"
  ( cd "$R" && git add -A && git commit -qm "bootstrap grandfather at cutover" ) >/dev/null 2>&1
  local S3_SHA; S3_SHA="$(cd "$R" && git rev-parse HEAD)"
  # Range spans the cutover commit, so legacy.sh IS in the ACMR diff and is
  # genuinely subjected to the coverage check rather than skipped.
  rc="$(run origin "refs/heads/master $S3_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "0" ]] && pass "genuinely grandfathered push ALLOWED (rc=0)" || fail "blocked despite grandfather coverage (rc=$rc)"

  echo "Scenario 3b: BLOCK — a SELF-AUTHORED grandfather row does NOT cover new content"
  # The C2-A bypass, as a regression test: brand-new unreviewed content plus a
  # grandfather row naming it, both committed in the same push. PROVEN to
  # return rc=0 before the cutover_ref binding landed.
  echo '# unreviewed, never at cutover' > "$R/adapters/claude-code/hooks/lib/forged.sh"
  local forged_blob; forged_blob="$(cd "$R" && git hash-object adapters/claude-code/hooks/lib/forged.sh)"
  printf '{"cutover_ref":"%s","entries":[{"path":"adapters/claude-code/hooks/lib/forged.sh","blob_sha":"%s"}]}\n' \
    "$CUTOVER_SHA" "$forged_blob" > "$R/docs/reviews/records/grandfather-manifest.json"
  ( cd "$R" && git add -A && git commit -qm "forge grandfather coverage" ) >/dev/null 2>&1
  local S3B_SHA; S3B_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S3B_SHA refs/heads/master $S3_SHA")"
  [[ "$rc" == "1" ]] && pass "self-authored grandfather row BLOCKED (rc=1)" \
    || fail "a self-authored grandfather row covered brand-new content (rc=$rc) — C2-A is open"

  echo "Scenario 3c: BLOCK — deleting BOTH coverage files does not fail open in the harness repo"
  # The C2-B bypass, as a regression test: `git rm` the coverage database in
  # the same push that carries unreviewed content. PROVEN rc=0 before the
  # bootstrap fail-open was scoped to non-harness repos.
  ( cd "$R" && git rm -q -f docs/reviews/records/index.json docs/reviews/records/grandfather-manifest.json \
      && git commit -qm "remove the coverage database" ) >/dev/null 2>&1
  local S3C_SHA; S3C_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S3C_SHA refs/heads/master $S3_SHA")"
  [[ "$rc" == "1" ]] && pass "coverage-database deletion BLOCKED (rc=1)" \
    || fail "deleting both coverage files failed open (rc=$rc) — C2-B is open"

  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/grandfather-manifest.json"
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add -A && git commit -qm "reset grandfather" ) >/dev/null 2>&1
  BASE_SHA="$(cd "$R" && git rev-parse HEAD)"

  echo "Scenario 4: OVERRIDE — a valid, fresh, SHA-matching marker allows the push"
  echo '# unreviewed, override path' > "$R/adapters/claude-code/hooks/lib/emergency.sh"
  ( cd "$R" && git add -A && git commit -qm "feat: emergency fix" ) >/dev/null 2>&1
  local S4_SHA; S4_SHA="$(cd "$R" && git rev-parse HEAD)"
  local STATE="$T/state4"; mkdir -p "$STATE"
  printf 'SHA: %s\nGranted: now\nReason: production is down and this cannot wait for review\nRepo: %s\n' "$S4_SHA" "$R" \
    > "$STATE/review-record-push-override-${S4_SHA}-2026-01-01T00-00-00Z.txt"
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE" bash "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "valid override marker ALLOWS the push (rc=0)" || fail "valid override did not allow (rc=$rc)"
  if grep -q "production is down" "$STATE/../hs"/*review-record-push-gate-overrides.log 2>/dev/null \
     || grep -rq "production is down" "$T"/*/review-record-push-gate-overrides.log 2>/dev/null; then
    pass "override logged to an audit trail"
  else
    fail "override not logged anywhere findable"
  fi

  echo "Scenario 5: OVERRIDE — a marker for a DIFFERENT sha does not apply"
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$T/state-empty" bash "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "no marker at all -> still BLOCKS (rc=1)" || fail "blocked without a marker did not fire (rc=$rc)"
  local STATE5="$T/state5"; mkdir -p "$STATE5"
  printf 'SHA: %s\nGranted: now\nReason: production is down and this cannot wait for review\nRepo: %s\n' "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "$R" \
    > "$STATE5/review-record-push-override-deadbeefdeadbeefdeadbeefdeadbeefdeadbeef-2026-01-01T00-00-00Z.txt"
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE5" bash "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "marker for a DIFFERENT sha does not apply — still BLOCKS (rc=1)" \
    || fail "wrong-sha marker was honored (rc=$rc) — sha-scoping is broken"

  echo "Scenario 6: OVERRIDE — a STALE marker (past TTL) does not apply"
  local STATE6="$T/state6"; mkdir -p "$STATE6"
  printf 'SHA: %s\nGranted: stale\nReason: production is down and this cannot wait for review\nRepo: %s\n' "$S4_SHA" "$R" \
    > "$STATE6/review-record-push-override-${S4_SHA}-2020-01-01T00-00-00Z.txt"
  # Age the marker file itself past the 900s TTL.
  touch -t 202001010000 "$STATE6/review-record-push-override-${S4_SHA}-2020-01-01T00-00-00Z.txt" 2>/dev/null \
    || touch -d "2020-01-01" "$STATE6/review-record-push-override-${S4_SHA}-2020-01-01T00-00-00Z.txt" 2>/dev/null
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE6" bash "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "STALE marker does not apply — still BLOCKS (rc=1)" \
    || fail "stale marker was honored (rc=$rc) — TTL enforcement is broken"

  echo "Scenario 7: OVERRIDE — a hand-crafted marker with an INVALID reason does not apply"
  local STATE7="$T/state7"; mkdir -p "$STATE7"
  printf 'SHA: %s\nGranted: now\nReason: skip\nRepo: %s\n' "$S4_SHA" "$R" \
    > "$STATE7/review-record-push-override-${S4_SHA}-2026-01-01T00-00-00Z.txt"
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE7" bash "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "placeholder-reason marker does not apply — still BLOCKS (rc=1)" \
    || fail "invalid-reason marker was honored (rc=$rc) — reason re-validation is broken"

  echo "Scenario 8: REVIEW_RECORD_GATE_OVERRIDE (the commit-time env-var escape hatch) has NO effect here"
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$T/state-empty2" REVIEW_RECORD_GATE_OVERRIDE="production is down and this cannot wait" bash "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "commit-time env-var override is inert at the authoritative layer (still rc=1)" \
    || fail "REVIEW_RECORD_GATE_OVERRIDE bypassed the authoritative gate (rc=$rc) — Rule 2 violated"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1

  echo "Scenario 9: FP budget — non-master branch is never checked, even with uncovered content"
  echo '# unreviewed' > "$R/adapters/claude-code/hooks/lib/feature-only.sh"
  ( cd "$R" && git add -A && git commit -qm "feat: on a feature branch" ) >/dev/null 2>&1
  local S9_SHA; S9_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/feat/foo $S9_SHA refs/heads/feat/foo $BASE_SHA")"
  [[ "$rc" == "0" ]] && pass "non-master branch push allowed regardless of coverage" || fail "non-master branch was gated (rc=$rc) — false positive"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1

  echo "Scenario 10: FP budget — delete-push (local-sha all zeros) is allowed"
  rc="$(run origin "refs/heads/master $ZERO_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "0" ]] && pass "delete-push allowed" || fail "delete-push blocked (rc=$rc)"

  echo "Scenario 11: FP budget — a foreign repo (no manifest.json) is never gated"
  local FR="$T/foreign"; mkdir -p "$FR/scripts"
  ( cd "$FR" && git init -q . && git config user.email t@example.com && git config user.name T ) >/dev/null 2>&1
  echo '# deploy' > "$FR/scripts/deploy.sh"
  ( cd "$FR" && git add -A && git commit -qm base ) >/dev/null 2>&1
  local FBASE; FBASE="$(cd "$FR" && git rev-parse HEAD)"
  echo '# changed' >> "$FR/scripts/deploy.sh"
  ( cd "$FR" && git add -A && git commit -qm change ) >/dev/null 2>&1
  local FHEAD; FHEAD="$(cd "$FR" && git rev-parse HEAD)"
  rc="$(printf '%s\n' "refs/heads/master $FHEAD refs/heads/master $FBASE" | ( cd "$FR" && bash "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "foreign repo not gated" || fail "gated a foreign repo (rc=$rc)"

  echo "Scenario 11b: INFRA FAIL-OPEN IS LOUD — no jq means the push is announced as UNCHECKED"
  # harness-reviewer C3. PROVEN before this fix: with a shim PATH carrying
  # git/grep/sed but NOT jq, the gate returned rc=0 with ZERO bytes of stderr,
  # so `PATH=<no-jq> git push` was a one-token inline prefix that silently
  # defeated the authoritative review gate. It still fails OPEN (a missing
  # binary must not brick a machine's ability to push) -- what is asserted
  # here is that it can no longer do so INVISIBLY.
  local SHIM="$T/nojq"; mkdir -p "$SHIM"
  local _t _p
  for _t in git grep sed awk bash sh find sort head tail cat wc tr date mkdir rm cp mv ls dirname basename stat env mktemp cut; do
    _p="$(command -v "$_t" 2>/dev/null)"; [[ -n "$_p" ]] && ln -sf "$_p" "$SHIM/$_t"
  done
  if PATH="$SHIM" command -v jq >/dev/null 2>&1; then
    fail "self-test bug: the no-jq shim still exposes jq, so this scenario proves nothing"
  else
    # Re-use the golden-case uncovered push, which BLOCKS when jq is present.
    local nojq_err="$T/nojq-stderr.txt"
    printf '%s\n' "refs/heads/master $S1_SHA refs/heads/master $ORIG_BASE_SHA" \
      | ( cd "$R" && PATH="$SHIM" bash "$SELF" origin ) >/dev/null 2>"$nojq_err"
    local nojq_msg; nojq_msg="$(cat "$nojq_err" 2>/dev/null)"
    if [[ -n "$nojq_msg" ]]; then
      pass "a jq-less run emits a warning instead of silence ($(printf '%s' "$nojq_msg" | wc -c | tr -d ' ') bytes)"
    else
      fail "a jq-less run produced ZERO bytes of stderr — the gate is silently defeated by a PATH prefix"
    fi
    case "$nojq_msg" in
      *"NOT*"*|*"NOT"*) pass "the warning states plainly that this push was NOT checked" ;;
      *) fail "the warning does not say the push went unchecked" ;;
    esac
    case "$nojq_msg" in
      *jq*) pass "the warning names the missing dependency" ;;
      *) fail "the warning does not name what was missing" ;;
    esac
  fi

  echo "Scenario 12: FP budget — a docs-only change in range is allowed"
  mkdir -p "$R/docs"
  echo 'notes' > "$R/docs/notes.md"
  ( cd "$R" && git add -A && git commit -qm "docs: notes" ) >/dev/null 2>&1
  local S12_SHA; S12_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S12_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "0" ]] && pass "docs-only push allowed" || fail "docs-only push blocked (rc=$rc)"
  BASE_SHA="$S12_SHA"

  echo "Scenario 13: first-push (remote-sha all zeros) — uncovered content anywhere in history still BLOCKS"
  local FP="$T/firstpush"; mkdir -p "$FP/adapters/claude-code/hooks/lib" "$FP/docs/reviews/records"
  printf '{"schema_version":1,"entries":[]}\n' > "$FP/adapters/claude-code/manifest.json"
  ( cd "$FP" && git init -q . && git config user.email t@example.com && git config user.name T ) >/dev/null 2>&1
  printf '{"entries":[]}\n' > "$FP/docs/reviews/records/index.json"
  printf '{"entries":[]}\n' > "$FP/docs/reviews/records/grandfather-manifest.json"
  ( cd "$FP" && git add -A && git commit -qm root ) >/dev/null 2>&1
  echo '# uncovered from the very first push' > "$FP/adapters/claude-code/hooks/lib/x.sh"
  ( cd "$FP" && git add -A && git commit -qm "feat: x" ) >/dev/null 2>&1
  local FP_HEAD; FP_HEAD="$(cd "$FP" && git rev-parse HEAD)"
  rc="$(printf '%s\n' "refs/heads/master $FP_HEAD refs/heads/master $ZERO_SHA" | ( cd "$FP" && bash "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "first-push with uncovered content BLOCKS (rc=1)" || fail "first-push uncovered content was not caught (rc=$rc)"

  echo "Scenario 13b: UNRESOLVABLE remote_sha (git diff fails) falls back to empty-tree scan, not silent allow"
  # harness-reviewer PROVEN reachability: a real bare-remote fixture shows
  # pre-push firing with a remote_sha the local object store does not have,
  # on BOTH a plain push and a --force push (fetch-first races, force-push
  # after a remote rewrite). Simulate that exact shape: a remote_sha that is
  # a well-formed but NONEXISTENT sha, so `git diff remote_sha..local_sha`
  # fails outright rather than returning an empty/degenerate result.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# unreviewed, unresolvable-range fixture' > "$R/adapters/claude-code/hooks/lib/unresolvable-range.sh"
  ( cd "$R" && git add -A && git commit -qm "feat: unresolvable range fixture" ) >/dev/null 2>&1
  local S13B_SHA; S13B_SHA="$(cd "$R" && git rev-parse HEAD)"
  local BOGUS_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"   # well-formed, does not exist
  rc="$(run origin "refs/heads/master $S13B_SHA refs/heads/master $BOGUS_SHA")"
  [[ "$rc" == "1" ]] && pass "unresolvable remote_sha falls back to scanning the full pushed tree — still BLOCKS (rc=1)" \
    || fail "FAIL-OPEN: a git-diff failure was scored as an empty (clean) file list (rc=$rc)"
  local msg13b; msg13b="$(run_capture origin "refs/heads/master $S13B_SHA refs/heads/master $BOGUS_SHA")"
  case "$msg13b" in *"could not compute the exact pushed range"*) pass "block message discloses the range-computation fallback (not silently reusing the precise-path wording)" ;; \
    *) fail "fallback fired but the block message never says so"; esac
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1

  echo "Scenario 14: integration — the real authorize script writes a marker this gate honors"
  local ARSCRIPT="$_RRPG_SELF_DIR/../scripts/authorize-review-record-push-override.sh"
  if [[ -f "$ARSCRIPT" ]]; then
    ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
    echo '# unreviewed, integration path' > "$R/adapters/claude-code/hooks/lib/integration.sh"
    ( cd "$R" && git add -A && git commit -qm "feat: integration" ) >/dev/null 2>&1
    local S14_SHA; S14_SHA="$(cd "$R" && git rev-parse HEAD)"
    local STATE14="$T/state14"; mkdir -p "$STATE14"
    ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE14" \
        bash "$ARSCRIPT" "production is down and this hotfix cannot wait for review" ) >/dev/null 2>&1
    rc="$(printf '%s\n' "refs/heads/master $S14_SHA refs/heads/master $BASE_SHA" \
          | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE14" bash "$SELF" origin ) >/dev/null 2>&1; echo $?)"
    [[ "$rc" == "0" ]] && pass "marker written by the real authorize script is honored by the gate (rc=0)" \
      || fail "gate did not honor a marker from the real authorize script (rc=$rc)"
  else
    fail "authorize-review-record-push-override.sh not found next to this gate — cannot verify the integration"
  fi
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1

  # ==========================================================================
  # Scenario 15: MUTATION-PROOF — neuter the gate's own block decision and
  # confirm the golden-case scenario (1) would then INCORRECTLY pass. This
  # proves the rc=1 asserted above is genuinely load-bearing (sensitive to
  # the real enforcement code), not a coincidence of the fixture.
  # ==========================================================================
  echo "Scenario 15: MUTATION-PROOF — a neutered gate must fail the golden-case block"
  # The mutant lives in a SANDBOX THAT CARRIES ITS OWN lib/ copy. Without it,
  # _RRPG_SELF_DIR points at a directory with no lib/review-record-gate-lib.sh
  # and the gate's missing-library block (CRITICAL 1 follow-on) fires first --
  # the mutant would "block" for a reason that has nothing to do with the
  # mutation, and the scenario would prove nothing while looking green.
  local MUTDIR="$T/mutant"; mkdir -p "$MUTDIR/lib"
  cp "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" "$MUTDIR/lib/" 2>/dev/null
  local MUTANT="$MUTDIR/mutant-gate.sh"
  # The decisive branch is `[[ "$saw_block" -eq 1 ]] && return 1`. Force it to
  # never block, leaving every OTHER line (detection, logging, messaging)
  # intact — this targets the ENFORCEMENT decision specifically, not the
  # detection logic, which is what a real regression of this kind would do.
  sed 's/\[\[ "\$saw_block" -eq 1 \]\] && return 1/[[ "$saw_block" -eq 1 ]] \&\& return 0/' "$SELF" > "$MUTANT"
  if grep -q '\[\[ "\$saw_block" -eq 1 \]\] && return 0' "$MUTANT"; then
    rc="$(printf '%s\n' "refs/heads/master $S1_SHA refs/heads/master $ORIG_BASE_SHA" \
          | ( cd "$R" && bash "$MUTANT" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" ]]; then
      pass "mutant (block decision neutered) WRONGLY allows the golden-case push (rc=0) — proves the real gate's rc=1 is load-bearing"
    else
      fail "mutant still blocked (rc=$rc) — the mutation did not land, this scenario proves nothing"
    fi
  else
    fail "could not construct the mutant (sed anchor not found — script drifted from what this scenario targets)"
  fi

  # ==========================================================================
  # CRITICAL 1 / MAJOR 3 (harness-reviewer, 2026-07-30). The PROVEN one-command
  # disarm: `git rm -f adapters/claude-code/manifest.json` in the same push as
  # unreviewed content. Before the identity anchor, this returned rc=0 with
  # ZERO bytes of stderr and landed the unreviewed file on a real bare remote.
  # ==========================================================================
  echo "Scenario 16: CRITICAL 1 — deleting the identity anchor BLOCKS, and says so"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  echo '# unreviewed harness change' > "$R/adapters/claude-code/hooks/lib/evil.sh"
  ( cd "$R" && git add -A && git rm -q -f adapters/claude-code/manifest.json \
      && git commit -qm "feat: evil + drop the identity anchor" ) >/dev/null 2>&1
  local S16_SHA; S16_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S16_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "1" ]] && pass "manifest-deletion push BLOCKED (rc=1)" \
    || fail "deleting manifest.json disarmed the gate (rc=$rc) — CRITICAL 1 is open"
  local msg16; msg16="$(run_capture origin "refs/heads/master $S16_SHA refs/heads/master $BASE_SHA")"
  # MAJOR 3: the scope test was the gate's FIRST decision and its ONE silent,
  # pusher-reachable fail-open. Loudness is asserted in BYTES, not just in
  # wording, because "0 bytes" was the actual observed failure.
  if [[ -n "$msg16" ]]; then
    pass "the disarm attempt is LOUD ($(printf '%s' "$msg16" | wc -c | tr -d ' ') bytes, was 0)"
  else
    fail "the disarm attempt produced ZERO bytes — a defeated gate is indistinguishable from a passing one"
  fi
  case "$msg16" in *manifest.json*) pass "message names the removed identity anchor" ;; \
    *) fail "message never names manifest.json"; esac

  echo "Scenario 17: CRITICAL 3 — a PURE deletion of an in-surface gate BLOCKS (--diff-filter=ACMR excluded D)"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  echo '# a gate that exists at the baseline' > "$R/adapters/claude-code/hooks/victim-gate.sh"
  ( cd "$R" && git add -A && git commit -qm "add victim gate" ) >/dev/null 2>&1
  local V_BASE; V_BASE="$(cd "$R" && git rev-parse HEAD)"
  ( cd "$R" && git rm -q -f adapters/claude-code/hooks/victim-gate.sh \
      && git commit -qm "chore: delete the gate" ) >/dev/null 2>&1
  local S17_SHA; S17_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S17_SHA refs/heads/master $V_BASE")"
  [[ "$rc" == "1" ]] && pass "pure deletion of an in-surface gate BLOCKED (rc=1)" \
    || fail "git rm of an in-surface gate was invisible to the gate (rc=$rc) — the D-filter hole is open"
  local msg17; msg17="$(run_capture origin "refs/heads/master $S17_SHA refs/heads/master $V_BASE")"
  case "$msg17" in *victim-gate.sh*) pass "message names the deleted file" ;; \
    *) fail "message omits the deleted file"; esac
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1

  echo "Scenario 18: the gate's own LIBRARY is repo content — deleting it BLOCKS in the harness repo, stays silent elsewhere"
  # PROVEN against the bare-remote fixture: `git rm` of lib/review-record-gate-
  # lib.sh alone took the gate to rc=0 (it could not source its own coverage
  # logic) and the deletion landed. A missing jq is a machine problem and fails
  # open loudly; a missing library is the harness repo disarming itself.
  local NOLIB="$T/nolib"; mkdir -p "$NOLIB"
  cp "$SELF" "$NOLIB/review-record-push-gate.sh"
  rc="$(printf '%s\n' "refs/heads/master $S1_SHA refs/heads/master $ORIG_BASE_SHA" \
        | ( cd "$R" && bash "$NOLIB/review-record-push-gate.sh" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "missing library in the harness repo BLOCKS (rc=1)" \
    || fail "deleting the gate's own library disarmed it (rc=$rc)"
  local nolib_foreign_err rc_f
  nolib_foreign_err="$(printf '%s\n' "refs/heads/master $FHEAD refs/heads/master $FBASE" \
        | ( cd "$FR" && bash "$NOLIB/review-record-push-gate.sh" origin ) 2>&1 >/dev/null)"
  rc_f="$(printf '%s\n' "refs/heads/master $FHEAD refs/heads/master $FBASE" \
        | ( cd "$FR" && bash "$NOLIB/review-record-push-gate.sh" origin ) >/dev/null 2>&1; echo $?)"
  if [[ "$rc_f" == "0" && -z "$nolib_foreign_err" ]]; then
    pass "a foreign repo with no library is silently ignored (rc=0, 0 bytes) — FP budget intact"
  else
    fail "the missing-library block leaked into a foreign repo (rc=$rc_f, stderr='$nolib_foreign_err')"
  fi

  echo "Scenario 19: CRITICAL 3 — the newly-covered carrier-chain arms are actually gated"
  # Each of these was NOT-COVERED before Amendment H, so the file that decides
  # whether the review gate runs could be changed with no review record.
  local arm armpath armlabel DISPATCHER_SHA=""
  for arm in "git-hooks/pre-push:the dispatcher" \
             "schemas/manifest.schema.json:the manifest schema" \
             "install.sh:the installer"; do
    armpath="${arm%%:*}"; armlabel="${arm#*:}"
    ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
    mkdir -p "$R/adapters/claude-code/$(dirname "$armpath")"
    echo '# unreviewed change to a carrier-chain link' > "$R/adapters/claude-code/$armpath"
    ( cd "$R" && git add -A && git commit -qm "touch $armpath" ) >/dev/null 2>&1
    local ARM_SHA; ARM_SHA="$(cd "$R" && git rev-parse HEAD)"
    [[ "$armpath" == "git-hooks/pre-push" ]] && DISPATCHER_SHA="$ARM_SHA"
    rc="$(run origin "refs/heads/master $ARM_SHA refs/heads/master $BASE_SHA")"
    [[ "$rc" == "1" ]] && pass "unreviewed $armlabel ($armpath) BLOCKS" \
      || fail "$armlabel ($armpath) is still unreviewable (rc=$rc)"
  done
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1

  # ==========================================================================
  # Scenario 19b: MUTATION-PROOF — the SURFACE ARM itself, isolated. Scenario
  # 19 asserts the dispatcher is gated; this proves that assertion is carried
  # by Amendment H's `git-hooks/*` case arm and would go red if the arm were
  # dropped. Without it, Scenario 19 could be passing for an unrelated reason
  # and the arm could be deleted with the suite still green -- which is
  # precisely how the surface drifted out of sync with the carrier chain in
  # the first place.
  # ==========================================================================
  echo "Scenario 19b: MUTATION-PROOF — deleting the git-hooks/* surface arm must re-open the unreviewed-dispatcher hole"
  local MUT4DIR="$T/mutant-surface"; mkdir -p "$MUT4DIR/lib"
  sed '/git-hooks\/\*) return 0 ;;/d' "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" \
    > "$MUT4DIR/lib/review-record-gate-lib.sh"
  cp "$SELF" "$MUT4DIR/gate.sh"
  if grep -q 'git-hooks/\*) return 0' "$MUT4DIR/lib/review-record-gate-lib.sh"; then
    fail "could not construct the surface mutant (the git-hooks arm survived the sed)"
  elif [[ -z "$DISPATCHER_SHA" ]]; then
    fail "Scenario 19 did not record a dispatcher-change commit — nothing to mutate against"
  else
    rc="$(printf '%s\n' "refs/heads/master $DISPATCHER_SHA refs/heads/master $BASE_SHA" \
          | ( cd "$R" && bash "$MUT4DIR/gate.sh" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" ]]; then
      pass "mutant (no git-hooks/* arm) WRONGLY allows the unreviewed dispatcher push (rc=0) — proves the surface arm is load-bearing"
    else
      fail "mutant still blocked (rc=$rc) — the surface mutation did not land, this scenario proves nothing"
    fi
  fi

  # ==========================================================================
  # Scenario 20: MUTATION-PROOF #2 — revert ONLY the identity anchor to the
  # pre-fix working-tree read and confirm the CRITICAL 1 attack succeeds again.
  # Scenario 15 proves the block DECISION is load-bearing; this proves the
  # ANCHOR is. Without it, Scenario 16 could be passing because of the D-filter
  # arm alone, and the anchor could rot untested.
  # ==========================================================================
  echo "Scenario 20: MUTATION-PROOF — reverting the identity anchor must re-open CRITICAL 1"
  # THE WORKING TREE MUST ACTUALLY LACK THE MANIFEST for this mutation to be
  # meaningful. The attacker's checkout is the post-`git rm` state, so that is
  # the state both gates must be judged against. Checking the mutant against a
  # tree that still HAS the manifest would let the pre-fix scope test pass, the
  # run would reach the (independent) deletion arm, and the mutant would
  # "block" for a reason the mutation never touched — a green scenario proving
  # nothing. The anchor and the deletion arm are deliberately redundant against
  # this attack; this scenario isolates the anchor by removing the deletion
  # arm's opportunity to fire.
  ( cd "$R" && git reset -q --hard "$S16_SHA" ) >/dev/null 2>&1
  if [[ -f "$R/adapters/claude-code/manifest.json" ]]; then
    fail "fixture bug: the working tree still carries manifest.json — Scenario 20 proves nothing"
  else
    pass "attacker's working tree genuinely lacks manifest.json (the pre-fix scope test's blind spot)"
  fi
  # The REAL gate must still block from this exact state — that is the whole
  # point of anchoring on the remote rather than the working tree.
  rc="$(run origin "refs/heads/master $S16_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "1" ]] && pass "real gate BLOCKS from a manifest-less working tree (rc=1)" \
    || fail "real gate failed open from a manifest-less working tree (rc=$rc)"
  local MUT2DIR="$T/mutant-anchor"; mkdir -p "$MUT2DIR/lib"
  cp "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" "$MUT2DIR/lib/" 2>/dev/null
  local MUTANT2="$MUT2DIR/gate.sh"
  # Delimiter is '#': the replacement text contains BOTH '/' (the path) and
  # '||' (the shell operator), so '/' and '|' are both unusable here. BSD sed
  # reports "bad flag in substitute command" rather than failing loudly at the
  # right place, which is exactly the kind of silently-wrong mutant this
  # scenario's own guard below is there to catch.
  sed 's#^  rrg_harness_identity "\$repo_root" .*#  [[ -f "$repo_root/adapters/claude-code/manifest.json" ]] || return 0#' \
    "$SELF" > "$MUTANT2"
  if grep -q '^  \[\[ -f "\$repo_root/adapters/claude-code/manifest.json" \]\] || return 0' "$MUTANT2"; then
    rc="$(printf '%s\n' "refs/heads/master $S16_SHA refs/heads/master $BASE_SHA" \
          | ( cd "$R" && bash "$MUTANT2" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" ]]; then
      pass "mutant (working-tree-anchored scope test) WRONGLY allows the manifest-deletion push (rc=0) — proves the anchor is load-bearing"
    else
      fail "mutant still blocked (rc=$rc) — the anchor mutation did not land, this scenario proves nothing"
    fi
  else
    fail "could not construct the anchor mutant (sed anchor not found — script drifted)"
  fi
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1

  # ==========================================================================
  # Scenario 21: MUTATION-PROOF #3 — the D-filter arm, isolated. Scenario 17
  # asserts a pure deletion blocks; this proves that assertion is carried by
  # the deletion enumeration and not by some incidental property of the
  # fixture. Targets a NON-manifest file so the identity anchor (which is
  # deliberately redundant for manifest.json) cannot mask the mutation.
  # ==========================================================================
  echo "Scenario 21: MUTATION-PROOF — dropping the deletion enumeration must re-open the git-rm hole"
  local MUT3DIR="$T/mutant-del"; mkdir -p "$MUT3DIR/lib"
  cp "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" "$MUT3DIR/lib/" 2>/dev/null
  local MUTANT3="$MUT3DIR/gate.sh"
  sed 's#^    deleted="\$(git -C .*#    deleted=""#' "$SELF" > "$MUTANT3"
  if grep -q '^    deleted=""$' "$MUTANT3"; then
    rc="$(printf '%s\n' "refs/heads/master $S17_SHA refs/heads/master $V_BASE" \
          | ( cd "$R" && bash "$MUTANT3" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" ]]; then
      pass "mutant (no deletion enumeration) WRONGLY allows the git-rm push (rc=0) — proves the D arm is load-bearing"
    else
      fail "mutant still blocked (rc=$rc) — the deletion mutation did not land, this scenario proves nothing"
    fi
  else
    fail "could not construct the deletion mutant (sed anchor not found — script drifted)"
  fi

  rm -rf "$T"
  unset HARNESS_SELFTEST_DIR
  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) export HARNESS_SELFTEST=1; _rrpg_self_test; exit $? ;;
    *) _rrpg_main "$@"; exit $? ;;
  esac
fi
