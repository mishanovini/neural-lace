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
# Main
# ------------------------------------------------------------

_rrpg_main() {
  local remote="${1:-}"
  local stdin_buf; stdin_buf="$(cat 2>/dev/null || true)"
  [[ -n "$stdin_buf" ]] || return 0
  [[ -n "$remote" ]] || return 0   # no remote name -> not our path

  command -v git >/dev/null 2>&1 || return 0
  command -v jq  >/dev/null 2>&1 || return 0

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [[ -f "$repo_root/adapters/claude-code/manifest.json" ]] || return 0   # not the harness repo

  # shellcheck source=/dev/null
  source "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" 2>/dev/null || return 0
  command -v rrg_in_surface >/dev/null 2>&1 || return 0
  command -v rrg_is_covered >/dev/null 2>&1 || return 0
  command -v rrg_blob_sha_of_ref >/dev/null 2>&1 || return 0
  command -v rrg_validate_waiver_reason >/dev/null 2>&1 || return 0

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

    local range files diff_rc range_degraded=0
    range="$(_rrpg_range "$local_sha" "$remote_sha")"
    files="$(git -C "$repo_root" diff --name-only --diff-filter=ACMR "$range" 2>/dev/null)"
    diff_rc=$?
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
    [[ -n "$files" ]] || continue

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

  echo "Scenario 3: PASS — grandfathered content allows the push"
  echo '# pre-cutover content' > "$R/adapters/claude-code/hooks/lib/legacy.sh"
  local leg_blob; leg_blob="$(cd "$R" && git hash-object adapters/claude-code/hooks/lib/legacy.sh)"
  printf '{"entries":[{"path":"adapters/claude-code/hooks/lib/legacy.sh","blob_sha":"%s"}]}\n' "$leg_blob" \
    > "$R/docs/reviews/records/grandfather-manifest.json"
  ( cd "$R" && git add -A && git commit -qm "feat: legacy content" ) >/dev/null 2>&1
  local S3_SHA; S3_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S3_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "0" ]] && pass "grandfathered push ALLOWED (rc=0)" || fail "blocked despite grandfather coverage (rc=$rc)"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/grandfather-manifest.json"
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
  local MUTANT="$T/mutant-gate.sh"
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
