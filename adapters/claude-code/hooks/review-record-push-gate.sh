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

# ===========================================================================
# PATH ENUMERATION PRIMITIVES — git's path OUTPUT ENCODING is not the path
# (harness-reviewer CRITICAL 2, round 4).
# ===========================================================================
#
# THE CLASS, stated so it generalizes past this gate: `git diff --name-only`
# does not emit paths. It emits a RENDERING of paths, and under git's default
# `core.quotePath=true` that rendering is C-quoted — the whole path is wrapped
# in double quotes and non-ASCII bytes become \NNN octal escapes. Feed that
# rendering to a path PREDICATE and the predicate answers a question about a
# string that is not the path.
#
# PROVEN end-to-end against a bare remote, BEFORE this fix: a brand-new
#   adapters/claude-code/hooks/pré-push-gate.sh
# pushed rc=0 with ZERO gate bytes and landed ON the remote, because
# `--name-only` emitted
#   "adapters/claude-code/hooks/pr\303\251-push-gate.sh"
# and rrg_in_surface returns OUT for that quoted form while returning IN for
# the raw path. THE PREDICATE WAS CORRECT AND THE CALLER WAS WRONG. This
# directly breached the gate's headline invariant and falsified the surface
# arms' own claim that "a new file of any kind under these trees is IN surface
# by default" — it was in-surface by default only for paths git chose not to
# quote.
#
# WHICH BYTES TRIGGER IT — measured, not assumed (probe output, git 2.x):
#   path                     plain      -c quotePath=false      -z (either)
#   ----                     -----      ------------------      -----------
#   pré-push-gate.sh         QUOTED     raw                     raw
#   back\slash.sh            QUOTED     STILL QUOTED            raw
#   two words.sh             raw        raw                     raw
#
# So `-c core.quotePath=false` ALONE IS NOT ENOUGH: backslash (and a literal
# double-quote) survive it, because quoting those is not what quotePath
# governs. A space, meanwhile, is never quoted — which is exactly why this
# defect hid: the obvious "weird path" probe passes.
#
# THE FIX IS BOTH TOKENS PLUS NUL FRAMING: `-c core.quotePath=false` for the
# encoding, `-z` for the framing, consumed with `while IFS= read -r -d ''`
# (bash 3.2.57 verified: 3/3 records incl. non-ASCII and backslash). NUL cannot
# survive a shell variable — command substitution strips it — so every
# enumeration goes to a FILE and is read from there. That is why these helpers
# take an outfile rather than echoing.
#
# RULE FOR THE NEXT GATE: every harness consumer of git path output must
# disable quoting AND use NUL separation before feeding a path to a predicate.
# The sibling consumers that feed THIS gate's surface predicate
# (review-record-commit-gate.sh, lib/review-queue-auto-enqueue-lib.sh) are
# fixed in the same commit; the wider harness-wide audit is filed as
# GIT-PATH-QUOTING-CLASS-01 in docs/backlog.md with its full enumeration.
# ---------------------------------------------------------------------------

_RRPG_TMPDIR=""
# _rrpg_ensure_tmpdir -- one scratch dir per invocation, removed on exit.
# rc 1 if it could not be created (callers must treat that as "cannot verify"
# and BLOCK, never as "nothing changed"). Read the result from
# $_RRPG_TMPDIR — deliberately NOT echoed.
#
# IT MUST NOT BE CALLED IN A COMMAND SUBSTITUTION, and that is why it does not
# echo. An earlier draft did `_tmp="$(_rrpg_tmpdir)"`, which runs the whole
# body in a SUBSHELL: the `trap ... EXIT` was registered on the subshell and
# fired the instant the substitution closed, so every enumeration below wrote
# into a directory that had already been removed. Every arm then failed, every
# push took the uncomputable branch, and 17 previously-green scenarios went
# red at once — fail-CLOSED, so it was loud, but it is the exact shape of a
# "cleanup ran too early" bug that fails OPEN in a gate built the other way
# round.
_rrpg_ensure_tmpdir() {
  [[ -n "$_RRPG_TMPDIR" ]] && return 0
  _RRPG_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/rrpg.XXXXXX" 2>/dev/null)" || return 1
  trap 'rm -rf "$_RRPG_TMPDIR" 2>/dev/null' EXIT
  return 0
}

# _rrpg_diff_z <repo_root> <outfile> <diff-args...> -- NUL-separated RAW paths.
# The two tokens are baked in here rather than at each call site precisely so a
# future caller cannot reintroduce CRITICAL 2 by forgetting one of them.
_rrpg_diff_z() {
  local repo_root="$1" out="$2"; shift 2
  git -C "$repo_root" -c core.quotePath=false diff --name-only -z "$@" > "$out" 2>/dev/null
}

# _rrpg_diff_raw_z <repo_root> <outfile> <range> -- NUL-separated --raw records.
# Record shape (verified by probe):  ":<srcmode> <dstmode> <srcsha> <dstsha> <status>" NUL "<path>" NUL
# --no-renames keeps it one path per record, so the two-read consumption loop
# below stays in frame.
_rrpg_diff_raw_z() {
  local repo_root="$1" out="$2"; shift 2
  git -C "$repo_root" -c core.quotePath=false diff --raw -z --no-renames "$@" > "$out" 2>/dev/null
}

# _rrpg_contains <needle> <haystack...> -- rc 0 iff needle is present.
_rrpg_contains() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
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
  # CLASS: decorated-list-element-reused-as-machine-argument (harness-reviewer
  # MAJOR 1, round 3). The human bullet list and the machine-readable
  # `--file ... --blob-sha ...` remedy are two DIFFERENT RENDERINGS of one set,
  # so they must not share a single decorated array. Annotating an element for
  # the bullet list ("foo.sh (DELETED by this push -- ...)") spliced the entire
  # decorated string into the remedy, emitting
  #   --file foo.sh (DELETED by this push -- ...) --blob-sha <blob-sha-of-...>
  # which is not a runnable command -- PROVEN by `bash -n` on the emitted
  # block: "syntax error near unexpected token '('". A gate that blocks while
  # printing an unrunnable way out is a gate with no way out.
  #
  # Parallel arrays are the fix: paths[] is ALWAYS bare (machine consumers),
  # disp[] carries the annotation (human consumers). Both are passed flattened
  # with an explicit count n because bash 3.2 cannot pass two arrays directly.
  # Self-test Scenario 22 `bash -n`s the emitted remedy so this cannot regress.
  local repo_root="$1" remote_ref="$2" sha="$3" degraded="$4" mode_hits="$5" n="$6"; shift 6
  local -a paths=() disp=()
  local _i
  for (( _i=0; _i<n; _i++ )); do paths+=("$1"); shift; done
  for (( _i=0; _i<n; _i++ )); do disp+=("$1"); shift; done
  {
    echo "================================================================"
    echo "REVIEW-RECORD PUSH GATE — PUSH BLOCKED (authoritative gate)"
    echo "================================================================"
    echo
    if [[ "$degraded" == "1" ]]; then
      echo "NOTE: could not compute the exact pushed range (the remote-tracked"
      echo "sha was unresolvable locally) — scanned the ENTIRE tree at $sha"
      echo "for changes, and used the remote-tracking ref as the baseline for"
      echo "the removal and mode arms. Some files listed below may already be"
      echo "on the remote from an earlier push; try \`git fetch\` first if this"
      echo "looks wrong."
      echo
    fi
    echo "Pushing $remote_ref at $sha would land UNREVIEWED harness content on"
    echo "the remote:"
    local f
    # HUMAN rendering -- annotations belong here and ONLY here.
    for f in "${disp[@]}"; do echo "  • $f"; done
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
    # THE REMEDY MUST BE SATISFIABLE, not merely runnable (Scenario 22's
    # principle, one layer up). For a MODE-ONLY change the review pathway is
    # structurally incapable of clearing the block: a review record attests to
    # {path, blob_sha}, the blob did not change, so the freshly-written record
    # is byte-identical to the coverage that already existed and the mode arm
    # fires again. Saying "get it reviewed" there would send the operator round
    # a loop that cannot terminate. Route 2 is the only route, and the block
    # says so rather than letting them discover it.
    if [[ "$mode_hits" == "1" ]]; then
      echo "ONE OR MORE ENTRIES ABOVE IS A FILE-MODE CHANGE. Read this first:"
      echo "a review record attests to {path, blob_sha}. A mode change leaves"
      echo "the blob identical, so REVIEWING IT CANNOT CLEAR THIS BLOCK — the"
      echo "record you would get back is the coverage you already have. For"
      echo "those entries, option 2 below is the ONLY route."
      echo
      echo "Why the mode is gated at all: git refuses to execute a hook that is"
      echo "not marked executable, so a 100755 → 100644 on a dispatcher under"
      echo "adapters/claude-code/git-hooks/ disarms the entire chain silently —"
      echo "and unlike a local \`core.hooksPath\` change, THIS ONE SHIPS to every"
      echo "clone. If the mode change is intentional, say so in the reason."
      echo
    fi
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
    # MACHINE rendering -- bare paths only. Splicing disp[] here is the MAJOR 1
    # defect this function's header describes; `bash -n` in Scenario 22 guards it.
    for f in "${paths[@]}"; do echo "         --file $f --blob-sha <blob-sha-of-$f-at-$sha> \\"; done
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

# _rrpg_uncomputable_block <remote_ref> <local_sha> <range> <why>
# AN ARM THAT COULD NOT BE COMPUTED IS NOT AN EMPTY ARM (harness-reviewer
# CRITICAL 1, round 4). The degraded path recomputes every arm of the subject
# set or lands here; there is deliberately no third option in which the gate
# continues with a subset. Loud, and it names WHICH arm and WHY, because the
# operator's next move differs: a `git fetch` fixes the usual cause outright.
_rrpg_uncomputable_block() {
  local remote_ref="$1" sha="$2" range="$3" why="$4"
  {
    echo "================================================================"
    echo "REVIEW-RECORD PUSH GATE — PUSH BLOCKED (subject set uncomputable)"
    echo "================================================================"
    echo "Could not compute the full set of files this push would change on"
    echo "$remote_ref at $sha."
    echo
    echo "Range attempted: $range"
    echo "What failed:     $why"
    echo
    echo "A gate that continues with a PARTIALLY computed subject set is a"
    echo "bypass that fires exactly when the gate is least sure of itself —"
    echo "so this refuses instead. The usual cause is that the remote has"
    echo "advanced and the local object store has never seen its tip:"
    echo
    echo "  git fetch --all && git push"
    echo
    echo "If the push is genuinely urgent and cannot wait for a fetch:"
    echo "  bash adapters/claude-code/scripts/authorize-review-record-push-override.sh \\"
    echo "    \"why this cannot wait for the range to be computable\" --sha $sha"
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

    local range diff_rc del_rc raw_rc range_degraded=0
    range="$(_rrpg_range "$local_sha" "$remote_sha")"

    # Every enumeration lands in a FILE (NUL framing cannot survive a
    # variable — see the PATH ENUMERATION PRIMITIVES header). A tmpdir we
    # cannot create is "cannot verify", not "nothing changed".
    # _rrpg_refuse <why> -- the ONE exit used by every uncomputable-arm path.
    # Honours the operator override FIRST: the block message it would
    # otherwise print names the override as the way out, and a remedy that
    # the code does not actually accept is the Scenario-22 defect one layer
    # up (runnable, but not satisfiable).
    _rrpg_refuse() {
      local why="$1" _o
      if _o="$(_rrpg_fresh_override "$local_sha")" && [[ -n "$_o" ]]; then
        _rrpg_log_override "$local_sha" "$_o" "$repo_root"
        echo "review-record-push-gate: OVERRIDDEN for $local_sha — \"$_o\" (logged for audit; subject set was uncomputable: $why)" >&2
        return 1
      fi
      saw_block=1
      _rrpg_uncomputable_block "$remote_ref" "$local_sha" "$range" "$why"
      return 0
    }

    local _tmp
    if ! _rrpg_ensure_tmpdir; then
      _rrpg_refuse "could not create a scratch directory for the path enumerations"
      continue
    fi
    _tmp="$_RRPG_TMPDIR"
    local F_CHANGED="$_tmp/changed.z" F_DELETED="$_tmp/deleted.z" F_RAW="$_tmp/raw.z"
    # ------------------------------------------------------------
    # ENUMERATE BY THE CODES THROUGH WHICH THE SUBJECT CAN CHANGE **OR LEAVE**
    # THE SURFACE -- not by a hand-picked filter list. (harness-reviewer
    # CRITICAL 1, round 3.)
    #
    # THE CLASS, stated so it generalizes past this gate: "the enforcing file
    # is gone from its enforcing path" is ONE OUTCOME reachable by FOUR VERBS,
    # and `git diff` scores each differently:
    #
    #   verb          name-status            ACMR sees      D sees
    #   ----          -----------            ---------      ------
    #   edit          M <path>               <path>         --
    #   git rm        D <path>               --             <path>
    #   git mv        R100 <old> <new>       <new> ONLY     NOTHING
    #   typechange    T <path>               --             --
    #
    # So the previous ACMR + D pair closed edit and rm while leaving BOTH mv
    # and typechange wide open: a rename reports only the DESTINATION (which,
    # moved out of surface, rrg_in_surface correctly rejects -- and the source
    # silently vanishes), and a regular-file->symlink typechange is excluded by
    # BOTH filters. PROVEN end-to-end against a bare remote: `git mv
    # hooks/victim-gate.sh docs/victim-gate.sh` pushed rc=0 with ZERO gate
    # bytes emitted, and the path was gone from the remote.
    #
    # A FIFTH VERB: the file stays, the bytes stay, and the MODE changes.
    # (harness-reviewer CRITICAL 3, round 4.)
    #
    #   verb                     name-status   ACMRT sees   D sees   coverage
    #   ----                     -----------   ----------   ------   --------
    #   chmod -x (mode only)     M <path>      <path>       --       PASSES
    #
    # A mode-only change IS enumerated as M, but the coverage key is
    # {path, blob_sha} and the blob is UNCHANGED — so rrg_is_covered returns
    # true and the gate waves it through. PROVEN against a bare remote:
    # `git update-index --chmod=-x adapters/claude-code/git-hooks/pre-push`
    # pushed rc=0, gate SILENT, and the remote carries mode 100644 for the
    # dispatcher that decides whether this whole chain runs. Mode is OUTSIDE
    # the coverage key entirely, so it is enumerated on its own arm below.
    #
    # THE FIX IS THREE TOKENS AND A FOURTH ARM, each measured before adoption.
    # RE-DERIVED 2026-07-30 over an EXPLICITLY NAMED population (harness-
    # reviewer MAJOR 1: the prior revision quoted 1763 while measuring 1593,
    # and the comparative it supported did not survive either denominator):
    #
    #   POPULATION — 1593 non-merge commits. Excluding merges is deliberate:
    #   a merge's `c^..c` diff re-attributes its whole side branch. Command:
    #     git rev-list --no-merges master | wc -l          -> 1593
    #     git rev-list master | wc -l                      -> 1763
    #     git rev-list --first-parent master | wc -l       -> 1106
    #   Per-arm command (in-surface paths only, rrg_in_surface applied):
    #     for c in $(git rev-list --no-merges master); do
    #       git -c core.quotePath=false diff --name-only -z <FILTER> "$c^..$c"
    #     done
    #
    #   * ACMR -> ACMRT    typechange.  0 commits /   0 files (0.00%) — free.
    #   * --no-renames     rename src.  7 commits /  38 files (0.44%).
    #   * D arm (already accepted)      8 commits / 104 files (0.50%).
    #   * MODE arm (new, ANY transition) 5 commits / 116 files (0.31%).
    #       of which 100755->100644 (the disarm direction) alone is
    #       1 commit / 1 file (0.06%), and 100644->100755 is 4 / 115 (0.25%).
    #
    # THE MODE ARM TAKES *ANY* TRANSITION, NOT JUST THE DISARM DIRECTION.
    # Restricting it to 100755->100644 would buy 0.25 percentage points and
    # cost a directional exemption branch in the very control that exists to
    # make metadata changes visible — the same reasoning that refused the
    # within-surface rename exemption one round ago. The honest statement is
    # the general one: the coverage key does not carry mode, in either
    # direction, so any mode transition is UNCOVERED. At 0.31% it is CHEAPER
    # than the deletion arm already accepted at 0.50% on the same population.
    #
    # RULE FOR THE NEXT GATE: every gate deriving a subject set from `git diff`
    # must enumerate by the codes through which its subject can change or LEAVE
    # the surface; and any control that authorizes CONTENT BY HASH must state
    # what metadata the hash does NOT cover (mode, symlink-ness, path encoding)
    # and either cover it or enumerate it as a named bypass. Scenarios
    # 17/17b/17c/17d/17e/17f/17g are that matrix — SEVEN cases, because the
    # matrix is the boundary of the last test run, never of the outcome.
    # ------------------------------------------------------------
    _rrpg_diff_z     "$repo_root" "$F_CHANGED" --diff-filter=ACMRT "$range"; diff_rc=$?
    # DELETIONS ARE PART OF THE SUBJECT SET (harness-reviewer CRITICAL 3,
    # round 2). --diff-filter=ACMR excludes D, so `git rm hooks/victim-gate.sh`
    # was a rc=0 no-op: deleting a gate was invisible to the gate. Enumerated
    # separately because a deleted path has no blob at local_sha, so it can
    # never take the ordinary coverage path. --no-renames additionally forces a
    # rename's SOURCE into this set (see the table above); without it, `git mv`
    # out of the surface is a silent rc=0.
    _rrpg_diff_z     "$repo_root" "$F_DELETED" --diff-filter=D --no-renames "$range"; del_rc=$?
    _rrpg_diff_raw_z "$repo_root" "$F_RAW" "$range"; raw_rc=$?

    if [[ "$diff_rc" -ne 0 || "$del_rc" -ne 0 || "$raw_rc" -ne 0 ]]; then
      range_degraded=1
      # ==========================================================
      # A DEGRADED SCAN RE-DERIVES **EVERY** ARM OR FAILS CLOSED.
      # (harness-reviewer CRITICAL 1, round 4.)
      #
      # THE CLASS: a fallback that recomputes a SUBSET of the subject set is a
      # bypass that fires exactly when the gate is least sure of itself. The
      # previous revision recomputed only `files` (ACMRT, from the empty tree)
      # and left `deleted` at its FAILED, empty value — and EMPTY_TREE..local
      # structurally cannot emit a D, so the entire deletion arm silently
      # vanished. PROVEN against a bare remote: remote advanced by one
      # unfetched commit, then `git rm` of an in-surface gate + push --force
      # -> rc=0, gate SILENT, divergence-check SILENT, path GONE from the
      # remote. The comment three lines up reasoned about not scanning "with a
      # WEAKER filter than the path it replaces" and then applied that
      # reasoning to only one of the two enumerations.
      #
      # PER-ARM rc, NOT ONE SHARED rc: `del_rc` and `raw_rc` are captured
      # independently above, because the change arm succeeding tells you
      # nothing about whether the removal arm did.
      #
      # THE CHANGE ARM degrades UPWARD: empty-tree..local_sha is a strict
      # SUPERSET of any range, so "scan everything in the pushed tree" is
      # never weaker than the range it replaces.
      #
      # THE REMOVAL AND MODE ARMS CANNOT: both are differential by nature and
      # need a REAL baseline. The remote-tracking refs are exactly that — the
      # pusher's last known remote state, an anchor this push does not write
      # (the same anchor the identity check above already trusts). Every
      # tracking ref that resolves contributes to a UNION, so a stale one can
      # only ADD subjects, never remove them. If NOT ONE resolves, the arms
      # are uncomputable and the push is REFUSED — never continued with a
      # silently empty arm.
      # ==========================================================
      _rrpg_diff_z "$repo_root" "$F_CHANGED" --diff-filter=ACMRT "${EMPTY_TREE}..${local_sha}"; diff_rc=$?

      : > "$F_DELETED"; : > "$F_RAW"
      local _bl _base_ok=0
      for _bl in $(rrg_remote_tracking_refs "$repo_root" "$remote_ref" 2>/dev/null); do
        git -C "$repo_root" rev-parse --verify --quiet "${_bl}^{commit}" >/dev/null 2>&1 || continue
        _rrpg_diff_z     "$repo_root" "$_tmp/d1.z" --diff-filter=D --no-renames "${_bl}..${local_sha}" || continue
        _rrpg_diff_raw_z "$repo_root" "$_tmp/r1.z" "${_bl}..${local_sha}" || continue
        cat "$_tmp/d1.z" >> "$F_DELETED"
        cat "$_tmp/r1.z" >> "$F_RAW"
        _base_ok=1
      done

      if [[ "$diff_rc" -ne 0 || "$_base_ok" -ne 1 ]]; then
        local _why="the deletion and mode arms could not be computed — no"
        _why="$_why remote-tracking ref for $remote_ref resolved to a commit, and"
        _why="$_why the empty tree structurally cannot report a removal or a mode"
        _why="$_why transition (it has nothing to remove FROM)"
        [[ "$diff_rc" -ne 0 ]] && _why="the change arm's empty-tree fallback also failed"
        _rrpg_refuse "$_why"
        continue
      fi
    fi
    [[ -s "$F_CHANGED" ]] || [[ -s "$F_DELETED" ]] || [[ -s "$F_RAW" ]] || continue

    # PARALLEL ARRAYS, kept in lockstep (see _rrpg_block_message's header):
    # uncovered_paths[] is the BARE path for machine consumers, uncovered[] is
    # the human rendering which may carry an annotation. Every push site below
    # appends to BOTH, in the same order.
    local -a uncovered=() uncovered_paths=()
    local mode_hits=0
    local f sha
    # NUL-FRAMED (CRITICAL 2): `read -r -d ''` from the enumeration FILE, never
    # a here-string over a variable — NUL cannot survive command substitution,
    # and a line-framed read is exactly what let a C-quoted path through.
    while IFS= read -r -d '' f; do
      [[ -n "$f" ]] || continue
      rrg_in_surface "$f" || continue
      sha="$(rrg_blob_sha_of_ref "$repo_root" "$local_sha" "$f" 2>/dev/null)" || sha=""
      if [[ -z "$sha" ]]; then
        # Bailouts resolve toward block (review-record-commit-gate.sh's own
        # hard-won principle): an unresolvable blob for a path the diff says
        # changed is "cannot verify", not "assume fine".
        uncovered_paths+=("$f")
        uncovered+=("$f (blob unresolvable at $local_sha)")
        continue
      fi
      if ! rrg_is_covered "$repo_root" "$local_sha" "$f" "$sha"; then
        uncovered_paths+=("$f")
        uncovered+=("$f")
      fi
    done < "$F_CHANGED"

    # In-surface DELETIONS **AND RENAME SOURCES** (--no-renames, above). A path
    # that left its location has no blob at local_sha, so rrg_is_covered can
    # never return true for it -- it is UNCOVERED by construction and the
    # operator override is its only route.
    #
    # MEASURED cost before choosing this, re-derived 2026-07-30 over a NAMED
    # population (harness-reviewer MAJOR 1 — the figures below previously
    # quoted 1763 while the scan that produced them excluded merges, and the
    # "cheaper than the accepted arm" comparative did not survive either
    # denominator). Population and command are stated in the enumeration
    # header above; both figures are over the SAME 1593 non-merge commits:
    #   * plain deletions   : 8 of 1593 non-merge commits (0.50%), 104 files.
    #   * rename sources    : 7 of 1593 (0.44%), 38 files, of which 37 are
    #                         renames OUT of the surface and 1 is a rename
    #                         WITHIN it (rules/conversation-tree-state.md ->
    #                         rules/workstreams-state.md, e272c3e).
    # The within-surface case is deliberately NOT suppressed: special-casing
    # "source vanished but destination is in-surface" would add an exemption
    # branch to the very control that exists to make vanishing hard, to save
    # one commit in 1593. The override exists for exactly this.
    # The historical hits are routine, not contrived -- scripts/
    # sync-pt-to-personal.sh -> attic/ and the ADR-058 rules/*.md ->
    # doctrine/*-full.md migration moved governance files off a reviewed
    # surface with zero coverage, which is the hole, not the noise.
    while IFS= read -r -d '' f; do
      [[ -n "$f" ]] || continue
      rrg_in_surface "$f" || continue
      _rrpg_contains "$f" ${uncovered_paths[@]+"${uncovered_paths[@]}"} && continue
      uncovered_paths+=("$f")
      uncovered+=("$f (DELETED by this push — removing an in-surface file needs the same authorization as changing it)")
    done < "$F_DELETED"

    # ------------------------------------------------------------
    # THE MODE ARM (harness-reviewer CRITICAL 3). Record shape, NUL-framed:
    #   ":<srcmode> <dstmode> <srcsha> <dstsha> <status>" NUL "<path>" NUL
    # so the loop reads TWO records per entry. --no-renames guarantees one path
    # per record, which is what keeps that pairing in frame.
    #
    # A 000000 on either side is a creation or a deletion, already enumerated
    # by the A and D arms — a mode TRANSITION needs two real modes, or the arm
    # would double-report every added file.
    # ------------------------------------------------------------
    local _meta _mpath _sm _dm
    while IFS= read -r -d '' _meta && IFS= read -r -d '' _mpath; do
      [[ -n "$_mpath" ]] || continue
      _sm="${_meta%% *}"; _sm="${_sm#:}"
      _dm="${_meta#* }"; _dm="${_dm%% *}"
      [[ "$_sm" == "$_dm" ]] && continue
      [[ "$_sm" == "000000" || "$_dm" == "000000" ]] && continue
      rrg_in_surface "$_mpath" || continue
      mode_hits=1
      _rrpg_contains "$_mpath" ${uncovered_paths[@]+"${uncovered_paths[@]}"} && continue
      uncovered_paths+=("$_mpath")
      uncovered+=("$_mpath (FILE MODE $_sm → $_dm — mode is OUTSIDE the {path, blob_sha} coverage key, so no review record can attest to it)")
    done < "$F_RAW"

    [[ "${#uncovered[@]}" -eq 0 ]] && continue

    local ovr
    if ovr="$(_rrpg_fresh_override "$local_sha")" && [[ -n "$ovr" ]]; then
      _rrpg_log_override "$local_sha" "$ovr" "$repo_root"
      echo "review-record-push-gate: OVERRIDDEN for $local_sha — \"$ovr\" (logged for audit)" >&2
      continue
    fi

    saw_block=1
    # Count first, then BOTH arrays flattened (bash 3.2 cannot pass two arrays).
    # Safe to expand unguarded: this line is unreachable when uncovered is empty
    # (the `-eq 0 && continue` above), which matters under `set -u` on bash 3.2.
    _rrpg_block_message "$repo_root" "$remote_ref" "$local_sha" "$range_degraded" "$mode_hits" \
      "${#uncovered_paths[@]}" "${uncovered_paths[@]}" "${uncovered[@]}"
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

  # ------------------------------------------------------------
  # THE CHILD GATE RUNS UNDER THE INTERPRETER BEING TESTED.
  #
  # Every scenario below drives the gate as a CHILD PROCESS. Those calls used
  # a bare `bash`, which resolves through PATH — on this machine that is
  # /opt/homebrew/bin/bash 5.3. So `/bin/bash review-record-push-gate.sh
  # --self-test` ran the harness under 3.2.57 while every gate body it
  # exercised ran under 5.3, and the portability floor was never actually
  # tested: a bash-4-only construct in the gate would have gone green on the
  # 3.2 run. $BASH is the absolute path of the interpreter currently running
  # this function, so both halves now agree.
  # ------------------------------------------------------------
  local _RRPG_TEST_BASH="${BASH:-bash}"
  echo "self-test interpreter: $_RRPG_TEST_BASH (${BASH_VERSION:-unknown})"

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
    printf '%s\n' "$2" | ( cd "$R" && "$_RRPG_TEST_BASH" "$SELF" "$1" ) >/dev/null 2>&1
    echo $?
  }
  run_capture() { # same, but echoes stderr
    printf '%s\n' "$2" | ( cd "$R" && "$_RRPG_TEST_BASH" "$SELF" "$1" ) 2>&1 >/dev/null
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
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE" "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "valid override marker ALLOWS the push (rc=0)" || fail "valid override did not allow (rc=$rc)"
  if grep -q "production is down" "$STATE/../hs"/*review-record-push-gate-overrides.log 2>/dev/null \
     || grep -rq "production is down" "$T"/*/review-record-push-gate-overrides.log 2>/dev/null; then
    pass "override logged to an audit trail"
  else
    fail "override not logged anywhere findable"
  fi

  echo "Scenario 5: OVERRIDE — a marker for a DIFFERENT sha does not apply"
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$T/state-empty" "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "no marker at all -> still BLOCKS (rc=1)" || fail "blocked without a marker did not fire (rc=$rc)"
  local STATE5="$T/state5"; mkdir -p "$STATE5"
  printf 'SHA: %s\nGranted: now\nReason: production is down and this cannot wait for review\nRepo: %s\n' "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "$R" \
    > "$STATE5/review-record-push-override-deadbeefdeadbeefdeadbeefdeadbeefdeadbeef-2026-01-01T00-00-00Z.txt"
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE5" "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
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
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE6" "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "STALE marker does not apply — still BLOCKS (rc=1)" \
    || fail "stale marker was honored (rc=$rc) — TTL enforcement is broken"

  echo "Scenario 7: OVERRIDE — a hand-crafted marker with an INVALID reason does not apply"
  local STATE7="$T/state7"; mkdir -p "$STATE7"
  printf 'SHA: %s\nGranted: now\nReason: skip\nRepo: %s\n' "$S4_SHA" "$R" \
    > "$STATE7/review-record-push-override-${S4_SHA}-2026-01-01T00-00-00Z.txt"
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE7" "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "placeholder-reason marker does not apply — still BLOCKS (rc=1)" \
    || fail "invalid-reason marker was honored (rc=$rc) — reason re-validation is broken"

  echo "Scenario 8: REVIEW_RECORD_GATE_OVERRIDE (the commit-time env-var escape hatch) has NO effect here"
  rc="$(printf '%s\n' "refs/heads/master $S4_SHA refs/heads/master $BASE_SHA" \
        | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$T/state-empty2" REVIEW_RECORD_GATE_OVERRIDE="production is down and this cannot wait" "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
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
  rc="$(printf '%s\n' "refs/heads/master $FHEAD refs/heads/master $FBASE" | ( cd "$FR" && "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
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
      | ( cd "$R" && PATH="$SHIM" "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>"$nojq_err"
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
  rc="$(printf '%s\n' "refs/heads/master $FP_HEAD refs/heads/master $ZERO_SHA" | ( cd "$FP" && "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "first-push with uncovered content BLOCKS (rc=1)" || fail "first-push uncovered content was not caught (rc=$rc)"

  echo "Scenario 13b: UNRESOLVABLE remote_sha with NO usable baseline — REFUSES (never continues on a partial subject set)"
  # harness-reviewer PROVEN reachability: a real bare-remote fixture shows
  # pre-push firing with a remote_sha the local object store does not have,
  # on BOTH a plain push and a --force push (fetch-first races, force-push
  # after a remote rewrite). Simulate that exact shape: a remote_sha that is
  # a well-formed but NONEXISTENT sha, so `git diff remote_sha..local_sha`
  # fails outright rather than returning an empty/degenerate result.
  #
  # THIS FIXTURE HAS NO REMOTE CONFIGURED, so there is no remote-tracking ref
  # to re-derive the removal and mode arms from. Under the round-4 rule
  # ("re-derive EVERY arm or fail closed") that is not a degraded scan, it is
  # an UNCOMPUTABLE one, and the gate must refuse rather than scan a subset.
  # Scenario 13c below is the same failure WITH a usable baseline.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# unreviewed, unresolvable-range fixture' > "$R/adapters/claude-code/hooks/lib/unresolvable-range.sh"
  ( cd "$R" && git add -A && git commit -qm "feat: unresolvable range fixture" ) >/dev/null 2>&1
  local S13B_SHA; S13B_SHA="$(cd "$R" && git rev-parse HEAD)"
  local BOGUS_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"   # well-formed, does not exist
  ( cd "$R" && git remote 2>/dev/null | grep -q . ) \
    && fail "fixture bug: \$R has a remote configured — Scenario 13b no longer isolates the no-baseline case" \
    || pass "fixture genuinely has no remote-tracking ref to fall back to"
  rc="$(run origin "refs/heads/master $S13B_SHA refs/heads/master $BOGUS_SHA")"
  [[ "$rc" == "1" ]] && pass "unresolvable remote_sha with no baseline REFUSES (rc=1)" \
    || fail "FAIL-OPEN: a git-diff failure was scored as an empty (clean) file list (rc=$rc)"
  local msg13b; msg13b="$(run_capture origin "refs/heads/master $S13B_SHA refs/heads/master $BOGUS_SHA")"
  case "$msg13b" in *"subject set uncomputable"*) pass "block message says the SUBJECT SET was uncomputable, not that the tree was clean" ;; \
    *) fail "refusal fired but the block message never says why"; esac
  case "$msg13b" in *"deletion and mode arms could not be computed"*) pass "message names WHICH arms could not be computed" ;; \
    *) fail "message does not name the uncomputable arms"; esac
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1

  # ==========================================================================
  # Scenario 13c/13d: THE DEGRADED-RANGE FALLBACK. (harness-reviewer CRITICAL
  # 1, round 4.)
  #
  # THE DEFECT: the fallback recomputed `files` with ACMRT from EMPTY_TREE..
  # local_sha but left `deleted` at its FAILED (empty) value -- and
  # EMPTY_TREE..local structurally cannot emit a D, so the ENTIRE deletion arm
  # silently vanished exactly when the gate was least sure of itself. PROVEN
  # against a bare remote: remote advanced by one unfetched commit, then
  # `git rm` of an in-surface gate + `git push --force` -> rc=0, gate SILENT,
  # divergence-check SILENT, path GONE from the remote.
  #
  # 13c fixes the ARM (a removal survives the degrade); 13d fixes nothing new
  # but pins that the degrade still ANNOUNCES itself, which is how an operator
  # tells "scanned precisely" from "scanned from a stale baseline".
  # ==========================================================================
  echo "Scenario 13c: CRITICAL 1 — a DELETION must survive the degraded-range fallback (was: silently dropped)"
  # A fixture WITH a remote-tracking ref: clone the repo so origin/master
  # exists as a real, resolvable baseline the push does not write.
  local DG="$T/degraded"
  git clone -q "$R" "$DG" >/dev/null 2>&1
  ( cd "$DG" && git config user.email t@example.com && git config user.name T ) >/dev/null 2>&1
  echo '# an in-surface gate present at the baseline' > "$DG/adapters/claude-code/hooks/degraded-victim.sh"
  ( cd "$DG" && git add -A ) >/dev/null 2>&1
  # COVER **EVERY** IN-SURFACE FILE IN THIS FIXTURE, not just the victim.
  # The degraded path scans EMPTY_TREE..local_sha for the change arm, i.e. the
  # WHOLE pushed tree — so any other uncovered in-surface file (the gate copy,
  # the lib copy, manifest.json) would block this push for a reason that has
  # nothing to do with the deletion arm, and Scenario 13c plus its mutation
  # proof would both be green while proving nothing. The rc=0 control below
  # is what turns that from an assumption into a check.
  _dg_cover_all() {
    local f s first=1
    { printf '{"entries":['
      for f in $(cd "$DG" && git ls-files); do
        case "$f" in adapters/claude-code/*) ;; *) continue ;; esac
        s="$(cd "$DG" && git hash-object "$f")"
        [[ $first -eq 1 ]] || printf ','
        first=0
        printf '{"path":"%s","blob_sha":"%s","kind":"harness-change-review","verdict":"PASS"}' "$f" "$s"
      done
      printf ']}\n'
    } > "$DG/docs/reviews/records/index.json"
  }
  _dg_cover_all
  ( cd "$DG" && git add -A && git commit -qm "add the victim; cover every in-surface file" ) >/dev/null 2>&1
  # Move origin/master forward to the victim-present state so the tracking ref
  # is a baseline in which the file EXISTS -- otherwise its removal is not
  # visible from that baseline and the scenario would prove nothing.
  ( cd "$DG" && git update-ref refs/remotes/origin/master HEAD ) >/dev/null 2>&1
  local DG_WITH_VICTIM; DG_WITH_VICTIM="$(cd "$DG" && git rev-parse HEAD)"
  # Guard: origin/master must really exist and really carry the victim, or the
  # baseline this scenario depends on is not there.
  if ( cd "$DG" && git cat-file -e "refs/remotes/origin/master:adapters/claude-code/hooks/degraded-victim.sh" 2>/dev/null ); then
    pass "fixture: origin/master carries the victim, so its removal is visible from that baseline"
  else
    fail "fixture bug: origin/master does not carry the victim — Scenario 13c proves nothing"
  fi
  # THE CONTROL: the very same DEGRADED push, with NOTHING deleted, must be
  # ALLOWED. If this is rc=1 the fixture has unrelated uncovered content and
  # every assertion below is meaningless.
  rc="$(printf '%s\n' "refs/heads/master $DG_WITH_VICTIM refs/heads/master $BOGUS_SHA" \
        | ( cd "$DG" && "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "CONTROL: the same degraded push with no deletion is ALLOWED (rc=0) — nothing unrelated is uncovered" \
    || fail "fixture bug: the degraded fixture blocks (rc=$rc) even with nothing deleted — Scenario 13c would prove nothing"
  ( cd "$DG" && git rm -q -f adapters/claude-code/hooks/degraded-victim.sh \
      && git commit -qm "chore: delete the gate under a degraded range" ) >/dev/null 2>&1
  local S13C_SHA; S13C_SHA="$(cd "$DG" && git rev-parse HEAD)"
  rc="$(printf '%s\n' "refs/heads/master $S13C_SHA refs/heads/master $BOGUS_SHA" \
        | ( cd "$DG" && "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "deletion under a DEGRADED range still BLOCKS (rc=1) — the removal arm was re-derived from the tracking ref" \
    || fail "CRITICAL 1 OPEN: the degraded fallback dropped the deletion arm (rc=$rc)"
  local msg13c; msg13c="$(printf '%s\n' "refs/heads/master $S13C_SHA refs/heads/master $BOGUS_SHA" \
        | ( cd "$DG" && "$_RRPG_TEST_BASH" "$SELF" origin ) 2>&1 >/dev/null)"
  case "$msg13c" in *degraded-victim.sh*) pass "message names the file deleted under the degraded range" ;; \
    *) fail "message omits the deleted file"; esac

  echo "Scenario 13d: the degraded scan ANNOUNCES itself (an operator must be able to tell it from a precise scan)"
  case "$msg13c" in *"could not compute the exact pushed range"*) pass "block message discloses that the range was degraded" ;; \
    *) fail "the scan degraded silently — indistinguishable from a precise scan"; esac
  case "$msg13c" in *"remote-tracking ref as the baseline"*) pass "message names WHICH baseline the removal/mode arms used" ;; \
    *) fail "message does not say which baseline the removal arm fell back to"; esac

  echo "Scenario 14: integration — the real authorize script writes a marker this gate honors"
  local ARSCRIPT="$_RRPG_SELF_DIR/../scripts/authorize-review-record-push-override.sh"
  if [[ -f "$ARSCRIPT" ]]; then
    ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
    echo '# unreviewed, integration path' > "$R/adapters/claude-code/hooks/lib/integration.sh"
    ( cd "$R" && git add -A && git commit -qm "feat: integration" ) >/dev/null 2>&1
    local S14_SHA; S14_SHA="$(cd "$R" && git rev-parse HEAD)"
    local STATE14="$T/state14"; mkdir -p "$STATE14"
    ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE14" \
        "$_RRPG_TEST_BASH" "$ARSCRIPT" "production is down and this hotfix cannot wait for review" ) >/dev/null 2>&1
    rc="$(printf '%s\n' "refs/heads/master $S14_SHA refs/heads/master $BASE_SHA" \
          | ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE14" "$_RRPG_TEST_BASH" "$SELF" origin ) >/dev/null 2>&1; echo $?)"
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
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUTANT" origin ) >/dev/null 2>&1; echo $?)"
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

  # ==========================================================================
  # Scenarios 17b/17c: THE OTHER TWO VERBS. (harness-reviewer CRITICAL 1,
  # round 3.) Scenario 17 closed `git rm`; these close `git mv` and the
  # regular-file->symlink typechange, which reach the SAME outcome -- the
  # enforcing file is gone from its enforcing path on the remote -- through
  # diff codes that ACMR+D never emitted. Both were PROVEN rc=0 with ZERO gate
  # bytes against a bare remote before the fix.
  # RULE: every new self-test carries a `git mv` case and a typechange case
  # beside its `git rm` case. One outcome, four verbs, four probes.
  # ==========================================================================
  echo "Scenario 17b: CRITICAL 1 — RENAMING an in-surface gate OUT of the surface BLOCKS (git mv: R100 emits only the destination)"
  ( cd "$R" && git reset -q --hard "$V_BASE" ) >/dev/null 2>&1
  ( cd "$R" && mkdir -p docs \
      && git mv adapters/claude-code/hooks/victim-gate.sh docs/victim-gate.sh \
      && git commit -qm "chore: move the gate out of the surface" ) >/dev/null 2>&1
  local S17MV_SHA; S17MV_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S17MV_SHA refs/heads/master $V_BASE")"
  [[ "$rc" == "1" ]] && pass "git mv of an in-surface gate out of the surface BLOCKED (rc=1)" \
    || fail "git mv out of the surface was invisible to the gate (rc=$rc) — the rename hole is open (needs --no-renames)"
  local msg17mv; msg17mv="$(run_capture origin "refs/heads/master $S17MV_SHA refs/heads/master $V_BASE")"
  case "$msg17mv" in *adapters/claude-code/hooks/victim-gate.sh*) \
    pass "message names the VANISHED SOURCE path, not just the destination" ;; \
    *) fail "message never names the source path that left the surface"; esac

  echo "Scenario 17c: CRITICAL 1 — a regular-file->symlink TYPECHANGE of an in-surface gate BLOCKS (T is excluded by BOTH ACMR and D)"
  ( cd "$R" && git reset -q --hard "$V_BASE" ) >/dev/null 2>&1
  ( cd "$R" && rm -f adapters/claude-code/hooks/victim-gate.sh \
      && ln -s /dev/null adapters/claude-code/hooks/victim-gate.sh \
      && git add -A && git commit -qm "chore: swap the gate for a symlink" ) >/dev/null 2>&1
  local S17TC_SHA; S17TC_SHA="$(cd "$R" && git rev-parse HEAD)"
  # Guard: the fixture must really be a typechange (mode 120000), or this
  # scenario would be asserting against an ordinary modification and prove
  # nothing about the T code.
  local tcmode; tcmode="$(cd "$R" && git ls-tree "$S17TC_SHA" adapters/claude-code/hooks/victim-gate.sh | awk '{print $1}')"
  [[ "$tcmode" == "120000" ]] && pass "fixture really is a typechange (mode 120000 at the pushed commit)" \
    || fail "fixture bug: expected mode 120000, got '$tcmode' — Scenario 17c proves nothing"
  rc="$(run origin "refs/heads/master $S17TC_SHA refs/heads/master $V_BASE")"
  [[ "$rc" == "1" ]] && pass "typechange of an in-surface gate BLOCKED (rc=1)" \
    || fail "regular-file->symlink typechange was invisible to the gate (rc=$rc) — the T hole is open (needs ACMRT)"
  local msg17tc; msg17tc="$(run_capture origin "refs/heads/master $S17TC_SHA refs/heads/master $V_BASE")"
  case "$msg17tc" in *victim-gate.sh*) pass "message names the typechanged file" ;; \
    *) fail "message omits the typechanged file"; esac

  # ==========================================================================
  # Scenarios 17e/17f: THE PATH IS NOT ITS RENDERING. (harness-reviewer
  # CRITICAL 2, round 4.) `git diff --name-only` C-quotes non-ASCII and
  # backslash under git's default core.quotePath, and rrg_in_surface answers
  # OUT for the quoted form while answering IN for the raw path -- so a brand
  # new in-surface file was classified out-of-surface and landed unreviewed.
  # PROVEN against a bare remote at rc=0 with ZERO gate bytes.
  #
  # 17f additionally pins the SPACE case as a CONTROL: a space is never
  # quoted, so it passed all along. That is exactly why this hid -- the
  # obvious "weird filename" probe is the one shape that was never broken.
  # ==========================================================================
  echo "Scenario 17e: CRITICAL 2 — a NON-ASCII in-surface path is gated (git C-quotes it: \"...pr\\303\\251...\")"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  printf '#!/bin/bash\n# brand new unreviewed harness code\n' > "$R/adapters/claude-code/hooks/pré-push-gate.sh"
  ( cd "$R" && git add -A && git commit -qm "feat: non-ascii gate" ) >/dev/null 2>&1
  local S17NA_SHA; S17NA_SHA="$(cd "$R" && git rev-parse HEAD)"
  # Guard: git must REALLY be quoting this path, or the scenario is asserting
  # against an ordinary ASCII path and proves nothing about the encoding.
  local q17; q17="$(cd "$R" && git diff --name-only "$BASE_SHA..$S17NA_SHA" | grep -c '^"' 2>/dev/null)"
  [[ "${q17:-0}" -ge 1 ]] && pass "fixture really is C-quoted by git's default --name-only rendering" \
    || fail "fixture bug: git did not quote the path — Scenario 17e proves nothing"
  rc="$(run origin "refs/heads/master $S17NA_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "1" ]] && pass "non-ASCII in-surface path BLOCKS (rc=1)" \
    || fail "a C-quoted path was classified OUT of surface and landed unreviewed (rc=$rc) — CRITICAL 2 is open"
  local msg17na; msg17na="$(run_capture origin "refs/heads/master $S17NA_SHA refs/heads/master $BASE_SHA")"
  case "$msg17na" in *"pré-push-gate.sh"*) pass "message names the file in its RAW form, not the C-quoted rendering" ;; \
    *) fail "message omits the non-ASCII file (or prints the escaped rendering)"; esac

  echo "Scenario 17f: CRITICAL 2 — a BACKSLASH path is gated (core.quotePath=false alone does NOT fix this one), and a SPACE path is the control"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  printf '#!/bin/bash\n# unreviewed\n' > "$R/adapters/claude-code/hooks/back\\slash.sh"
  ( cd "$R" && git add -A && git commit -qm "feat: backslash gate" ) >/dev/null 2>&1
  local S17BS_SHA; S17BS_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S17BS_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "1" ]] && pass "backslash in-surface path BLOCKS (rc=1)" \
    || fail "a backslash path was classified OUT of surface (rc=$rc) — the -z framing is missing"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  printf '#!/bin/bash\n# unreviewed\n' > "$R/adapters/claude-code/hooks/two words.sh"
  ( cd "$R" && git add -A && git commit -qm "feat: spaced gate" ) >/dev/null 2>&1
  local S17SP_SHA; S17SP_SHA="$(cd "$R" && git rev-parse HEAD)"
  rc="$(run origin "refs/heads/master $S17SP_SHA refs/heads/master $BASE_SHA")"
  [[ "$rc" == "1" ]] && pass "CONTROL: a space path blocks too (it always did — git never quotes a space)" \
    || fail "the space path regressed (rc=$rc)"

  # ==========================================================================
  # Scenario 17g: THE FIFTH VERB — MODE. (harness-reviewer CRITICAL 3,
  # round 4.) The file stays, the bytes stay, the mode changes: the coverage
  # key is {path, blob_sha}, so the blob still matches its PASS record and the
  # gate waved it through. PROVEN against a bare remote with
  # `git update-index --chmod=-x` on the pre-push DISPATCHER -- rc=0, gate
  # SILENT, remote carries 100644, and git refuses to run a non-executable
  # hook, so every clone from that point has the whole chain disarmed.
  # ==========================================================================
  echo "Scenario 17g: CRITICAL 3 — a MODE-ONLY change on a COVERED in-surface file BLOCKS (blob is unchanged, so coverage matched)"
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  mkdir -p "$R/adapters/claude-code/git-hooks"
  printf '#!/bin/bash\n# dispatcher\n' > "$R/adapters/claude-code/git-hooks/pre-push"
  chmod +x "$R/adapters/claude-code/git-hooks/pre-push"
  local disp_blob; disp_blob="$(cd "$R" && git hash-object adapters/claude-code/git-hooks/pre-push)"
  printf '{"entries":[{"path":"adapters/claude-code/git-hooks/pre-push","blob_sha":"%s","kind":"harness-change-review","verdict":"PASS"}]}\n' "$disp_blob" \
    > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add -A && git commit -qm "add a COVERED, executable dispatcher" ) >/dev/null 2>&1
  local MODE_BASE; MODE_BASE="$(cd "$R" && git rev-parse HEAD)"
  # Sanity: pushing the covered dispatcher must be ALLOWED, or the block below
  # could be firing on non-coverage rather than on the mode.
  rc="$(run origin "refs/heads/master $MODE_BASE refs/heads/master $BASE_SHA")"
  [[ "$rc" == "0" ]] && pass "baseline: the dispatcher is genuinely COVERED (rc=0) — a later block cannot be blamed on coverage" \
    || fail "fixture bug: the dispatcher is not covered (rc=$rc) — Scenario 17g would prove nothing"
  ( cd "$R" && git update-index --chmod=-x adapters/claude-code/git-hooks/pre-push \
      && git commit -qm "chore: index-only chmod -x of the dispatcher" ) >/dev/null 2>&1
  local S17MODE_SHA; S17MODE_SHA="$(cd "$R" && git rev-parse HEAD)"
  # Guard: the fixture must really be a MODE-ONLY change -- same blob, new mode.
  local m_before m_after b_before b_after
  m_before="$(cd "$R" && git ls-tree "$MODE_BASE" adapters/claude-code/git-hooks/pre-push | awk '{print $1}')"
  m_after="$(cd "$R" && git ls-tree "$S17MODE_SHA" adapters/claude-code/git-hooks/pre-push | awk '{print $1}')"
  b_before="$(cd "$R" && git rev-parse "$MODE_BASE:adapters/claude-code/git-hooks/pre-push")"
  b_after="$(cd "$R" && git rev-parse "$S17MODE_SHA:adapters/claude-code/git-hooks/pre-push")"
  if [[ "$m_before" == "100755" && "$m_after" == "100644" && "$b_before" == "$b_after" ]]; then
    pass "fixture really is MODE-ONLY (100755 -> 100644, blob unchanged at $b_after)"
  else
    fail "fixture bug: expected 100755->100644 with an unchanged blob, got $m_before->$m_after ($b_before vs $b_after)"
  fi
  rc="$(run origin "refs/heads/master $S17MODE_SHA refs/heads/master $MODE_BASE")"
  [[ "$rc" == "1" ]] && pass "mode-only disarm of the dispatcher BLOCKS (rc=1)" \
    || fail "a mode-only change passed coverage and landed (rc=$rc) — CRITICAL 3 is open"
  local msg17mode; msg17mode="$(run_capture origin "refs/heads/master $S17MODE_SHA refs/heads/master $MODE_BASE")"
  case "$msg17mode" in *"FILE MODE 100755"*) pass "message names the mode transition explicitly" ;; \
    *) fail "message does not name the mode transition"; esac
  # THE REMEDY MUST BE SATISFIABLE, not just runnable: for a mode-only change
  # the review pathway is structurally incapable of clearing the block (the
  # record would attest to the same blob it already attests to), so the block
  # must say so rather than sending the operator round a loop.
  case "$msg17mode" in *"REVIEWING IT CANNOT CLEAR THIS BLOCK"*) \
    pass "block states that review cannot clear a mode-only change, and routes to the override" ;; \
    *) fail "block offers the review pathway for a mode change it can never satisfy"; esac
  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add -A && git commit -qm "reset index after mode scenario" ) >/dev/null 2>&1
  BASE_SHA="$(cd "$R" && git rev-parse HEAD)"

  # ==========================================================================
  # Scenario 22: THE REMEDY MUST BE RUNNABLE. (harness-reviewer MAJOR 1.)
  # CLASS: decorated-list-element-reused-as-machine-argument. The human bullet
  # annotation ("foo.sh (DELETED by this push -- ...)") was spliced verbatim
  # into the machine-readable `--file`/`--blob-sha` remedy, so the command the
  # gate told the operator to run did not parse. A gate that blocks while
  # printing an unrunnable way out has no way out. `bash -n` is the oracle.
  # ==========================================================================
  echo "Scenario 22: MAJOR 1 — the remedy emitted on a DELETION block must actually parse as shell"
  local remedy
  remedy="$(printf '%s\n' "$msg17" | sed -n '/review-queue.sh enqueue/,/--repo-root \./p' | sed 's/^ *//')"
  if [[ -z "$remedy" ]]; then
    fail "could not extract the enqueue remedy from the block message — Scenario 22 proves nothing"
  elif printf '%s\n' "$remedy" | bash -n 2>/dev/null; then
    pass "emitted remedy parses under \`bash -n\` (annotation is not spliced into --file/--blob-sha)"
  else
    fail "emitted remedy is NOT runnable: $(printf '%s\n' "$remedy" | bash -n 2>&1 | head -1)"
  fi
  # The annotation must still reach the HUMAN list -- the fix must not have
  # been "drop the annotation everywhere", which would lose the explanation of
  # WHY a deletion is uncovered.
  case "$msg17" in *"DELETED by this push"*) \
    pass "the human bullet list still carries the DELETED annotation (fix split the renderings, did not drop the text)" ;; \
    *) fail "the DELETED annotation was lost from the human list — the remedy fix over-corrected"; esac
  # And the machine line must carry the BARE path with no parenthetical.
  case "$remedy" in *"--file adapters/claude-code/hooks/victim-gate.sh --blob-sha"*) \
    pass "--file carries the bare path immediately followed by --blob-sha" ;; \
    *) fail "--file argument is still decorated: $(printf '%s' "$remedy" | grep -- '--file' | head -1)"; esac

  ( cd "$R" && git reset -q --hard "$BASE_SHA" ) >/dev/null 2>&1

  echo "Scenario 18: the gate's own LIBRARY is repo content — deleting it BLOCKS in the harness repo, stays silent elsewhere"
  # PROVEN against the bare-remote fixture: `git rm` of lib/review-record-gate-
  # lib.sh alone took the gate to rc=0 (it could not source its own coverage
  # logic) and the deletion landed. A missing jq is a machine problem and fails
  # open loudly; a missing library is the harness repo disarming itself.
  local NOLIB="$T/nolib"; mkdir -p "$NOLIB"
  cp "$SELF" "$NOLIB/review-record-push-gate.sh"
  rc="$(printf '%s\n' "refs/heads/master $S1_SHA refs/heads/master $ORIG_BASE_SHA" \
        | ( cd "$R" && "$_RRPG_TEST_BASH" "$NOLIB/review-record-push-gate.sh" origin ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "missing library in the harness repo BLOCKS (rc=1)" \
    || fail "deleting the gate's own library disarmed it (rc=$rc)"
  local nolib_foreign_err rc_f
  nolib_foreign_err="$(printf '%s\n' "refs/heads/master $FHEAD refs/heads/master $FBASE" \
        | ( cd "$FR" && "$_RRPG_TEST_BASH" "$NOLIB/review-record-push-gate.sh" origin ) 2>&1 >/dev/null)"
  rc_f="$(printf '%s\n' "refs/heads/master $FHEAD refs/heads/master $FBASE" \
        | ( cd "$FR" && "$_RRPG_TEST_BASH" "$NOLIB/review-record-push-gate.sh" origin ) >/dev/null 2>&1; echo $?)"
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
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUT4DIR/gate.sh" origin ) >/dev/null 2>&1; echo $?)"
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
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUTANT2" origin ) >/dev/null 2>&1; echo $?)"
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
  sed 's#^    _rrpg_diff_z     "\$repo_root" "\$F_DELETED".*del_rc=\$?#    : > "$F_DELETED"; del_rc=0#' "$SELF" > "$MUTANT3"
  if grep -q '^    : > "\$F_DELETED"; del_rc=0$' "$MUTANT3"; then
    rc="$(printf '%s\n' "refs/heads/master $S17_SHA refs/heads/master $V_BASE" \
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUTANT3" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" ]]; then
      pass "mutant (no deletion enumeration) WRONGLY allows the git-rm push (rc=0) — proves the D arm is load-bearing"
    else
      fail "mutant still blocked (rc=$rc) — the deletion mutation did not land, this scenario proves nothing"
    fi
  else
    fail "could not construct the deletion mutant (sed anchor not found — script drifted)"
  fi

  # ==========================================================================
  # Scenario 21b: MUTATION-PROOF #4 — the --no-renames token, isolated.
  # Scenario 17b asserts a `git mv` out of the surface blocks; this proves that
  # assertion is carried by --no-renames specifically and not by some other arm
  # incidentally catching the same commit. Remove ONE token; the mv attack must
  # succeed again.
  # ==========================================================================
  echo "Scenario 21b: MUTATION-PROOF — dropping --no-renames must re-open the git-mv hole"
  local MUT5DIR="$T/mutant-norenames"; mkdir -p "$MUT5DIR/lib"
  cp "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" "$MUT5DIR/lib/" 2>/dev/null
  local MUTANT5="$MUT5DIR/gate.sh"
  sed 's#\(^    _rrpg_diff_z     "\$repo_root" "\$F_DELETED" --diff-filter=D\) --no-renames#\1#' "$SELF" > "$MUTANT5"
  if grep -q '^    _rrpg_diff_z     "\$repo_root" "\$F_DELETED" --diff-filter=D "\$range"' "$MUTANT5"; then
    rc="$(printf '%s\n' "refs/heads/master $S17MV_SHA refs/heads/master $V_BASE" \
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUTANT5" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" ]]; then
      pass "mutant (no --no-renames) WRONGLY allows the git-mv push (rc=0) — proves the token is load-bearing"
    else
      fail "mutant still blocked (rc=$rc) — the --no-renames mutation did not land, this scenario proves nothing"
    fi
  else
    fail "could not construct the --no-renames mutant (sed anchor not found — script drifted)"
  fi

  # ==========================================================================
  # Scenario 21c: MUTATION-PROOF #5 — the typechange, now DOUBLY covered.
  #
  # HONEST RESULT, recorded rather than engineered away: once the round-4 mode
  # arm landed, reverting ACMRT to ACMR was NO LONGER sufficient to re-open
  # the typechange hole — because a regular-file -> symlink IS a mode
  # transition (100644 -> 120000), so the mode arm catches it independently.
  # The single-token mutant went green-blocking and this scenario would have
  # read as "the mutation did not land" if left as written.
  #
  # Rather than contrive a mutant that isolates a now-redundant token, the
  # scenario asserts what is actually true, in two parts:
  #   (a) REDUNDANCY IS REAL — removing only the T still blocks. That is
  #       defense-in-depth, and it is worth pinning so a future reader does
  #       not "simplify" ACMRT back to ACMR believing it is free.
  #   (b) THE COVERAGE IS LOAD-BEARING — removing the T *and* the mode arm
  #       re-opens the hole, proving nothing else in the gate catches it.
  # ==========================================================================
  echo "Scenario 21c: MUTATION-PROOF — the typechange is covered TWICE (ACMRT and the mode arm); removing both re-opens it"
  local MUT6DIR="$T/mutant-acmrt"; mkdir -p "$MUT6DIR/lib"
  cp "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" "$MUT6DIR/lib/" 2>/dev/null
  local MUTANT6="$MUT6DIR/gate.sh" MUTANT6B="$MUT6DIR/gate-both.sh"
  sed 's#\(^    _rrpg_diff_z     "\$repo_root" "\$F_CHANGED" --diff-filter=ACMR\)T#\1#' "$SELF" > "$MUTANT6"
  sed 's#^    _rrpg_diff_raw_z "\$repo_root" "\$F_RAW".*raw_rc=\$?#    : > "$F_RAW"; raw_rc=0#' "$MUTANT6" > "$MUTANT6B"
  if ! grep -q '^    _rrpg_diff_z     "\$repo_root" "\$F_CHANGED" --diff-filter=ACMR "\$range"' "$MUTANT6"; then
    fail "could not construct the ACMRT mutant (sed anchor not found — script drifted)"
  elif ! grep -q '^    : > "\$F_RAW"; raw_rc=0$' "$MUTANT6B"; then
    fail "could not construct the ACMRT+mode double mutant (sed anchor not found — script drifted)"
  else
    rc="$(printf '%s\n' "refs/heads/master $S17TC_SHA refs/heads/master $V_BASE" \
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUTANT6" origin ) >/dev/null 2>&1; echo $?)"
    [[ "$rc" == "1" ]] && pass "REDUNDANCY PROVEN: ACMR-only still blocks the typechange (rc=1) — the mode arm covers it independently" \
      || fail "ACMR-only allowed the typechange (rc=$rc) — the redundancy this scenario documents does not exist"
    rc="$(printf '%s\n' "refs/heads/master $S17TC_SHA refs/heads/master $V_BASE" \
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUTANT6B" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" ]]; then
      pass "double mutant (no T, no mode arm) WRONGLY allows the typechange push (rc=0) — proves nothing ELSE in the gate catches it"
    else
      fail "double mutant still blocked (rc=$rc) — the typechange mutation did not land, this scenario proves nothing"
    fi
  fi

  # ==========================================================================
  # Scenario 21d: MUTATION-PROOF #6 — the MODE arm, isolated. Scenario 17g
  # asserts a mode-only change blocks; this proves that assertion is carried
  # by the --raw enumeration and not by some other arm incidentally catching
  # the same commit (the blob IS covered there, so no other arm should).
  # ==========================================================================
  echo "Scenario 21d: MUTATION-PROOF — dropping the --raw mode enumeration must re-open the chmod hole"
  local MUT7DIR="$T/mutant-mode"; mkdir -p "$MUT7DIR/lib"
  cp "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" "$MUT7DIR/lib/" 2>/dev/null
  local MUTANT7="$MUT7DIR/gate.sh"
  sed 's#^    _rrpg_diff_raw_z "\$repo_root" "\$F_RAW".*raw_rc=\$?#    : > "$F_RAW"; raw_rc=0#' "$SELF" > "$MUTANT7"
  if grep -q '^    : > "\$F_RAW"; raw_rc=0$' "$MUTANT7"; then
    rc="$(printf '%s\n' "refs/heads/master $S17MODE_SHA refs/heads/master $MODE_BASE" \
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUTANT7" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" ]]; then
      pass "mutant (no mode enumeration) WRONGLY allows the chmod push (rc=0) — proves the mode arm is load-bearing"
    else
      fail "mutant still blocked (rc=$rc) — the mode mutation did not land, this scenario proves nothing"
    fi
  else
    fail "could not construct the mode mutant (sed anchor not found — script drifted)"
  fi

  # ==========================================================================
  # Scenario 21e: MUTATION-PROOF #7 — the DEGRADED-ARM re-derivation,
  # isolated. Restore the exact pre-fix shape (the fallback populates the
  # change arm and leaves the removal arm at its failed, empty value) and
  # confirm CRITICAL 1 succeeds again. Deleting ONE line is the whole defect.
  # ==========================================================================
  echo "Scenario 21e: MUTATION-PROOF — leaving the removal arm unpopulated in the degraded branch must re-open CRITICAL 1"
  local MUT8DIR="$T/mutant-degraded"; mkdir -p "$MUT8DIR/lib"
  cp "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" "$MUT8DIR/lib/" 2>/dev/null
  local MUTANT8="$MUT8DIR/gate.sh"
  sed '/cat "\$_tmp\/d1.z" >> "\$F_DELETED"/d' "$SELF" > "$MUTANT8"
  if grep -q 'cat "\$_tmp/d1.z" >> "\$F_DELETED"' "$MUTANT8"; then
    fail "could not construct the degraded-arm mutant (the cat survived the sed)"
  else
    rc="$(printf '%s\n' "refs/heads/master $S13C_SHA refs/heads/master $BOGUS_SHA" \
          | ( cd "$DG" && "$_RRPG_TEST_BASH" "$MUTANT8" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" ]]; then
      pass "mutant (removal arm left empty on degrade) WRONGLY allows the deletion push (rc=0) — proves the re-derivation is load-bearing"
    else
      fail "mutant still blocked (rc=$rc) — the degraded-arm mutation did not land, this scenario proves nothing"
    fi
  fi

  # ==========================================================================
  # Scenario 21f: MUTATION-PROOF #8 — the PATH ENCODING fix, isolated.
  # Restore BOTH halves of the pre-fix shape (line-framed `--name-only` with
  # git's default quoting, consumed by a line-framed `read -r`) and confirm
  # the non-ASCII path lands again. The mutant must stay DISCRIMINATING: it
  # has to keep blocking the plain-ASCII golden case, or it would be proving
  # "the gate stopped working" rather than "the encoding fix is load-bearing".
  # ==========================================================================
  echo "Scenario 21f: MUTATION-PROOF — reverting to line-framed, C-quoted enumeration must re-open the non-ASCII hole"
  local MUT9DIR="$T/mutant-quote"; mkdir -p "$MUT9DIR/lib"
  cp "$_RRPG_SELF_DIR/lib/review-record-gate-lib.sh" "$MUT9DIR/lib/" 2>/dev/null
  local MUTANT9="$MUT9DIR/gate.sh"
  sed -e 's#git -C "\$repo_root" -c core.quotePath=false diff --name-only -z "\$@" > "\$out"#git -C "$repo_root" diff --name-only "$@" > "$out"#' \
      -e "s#while IFS= read -r -d '' f; do#while IFS= read -r f; do#" \
      "$SELF" > "$MUTANT9"
  if grep -q 'git -C "\$repo_root" diff --name-only "\$@" > "\$out"' "$MUTANT9" \
     && ! grep -q "while IFS= read -r -d '' f; do" "$MUTANT9"; then
    rc="$(printf '%s\n' "refs/heads/master $S17NA_SHA refs/heads/master $BASE_SHA" \
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUTANT9" origin ) >/dev/null 2>&1; echo $?)"
    local rc_ascii; rc_ascii="$(printf '%s\n' "refs/heads/master $S1_SHA refs/heads/master $ORIG_BASE_SHA" \
          | ( cd "$R" && "$_RRPG_TEST_BASH" "$MUTANT9" origin ) >/dev/null 2>&1; echo $?)"
    if [[ "$rc" == "0" && "$rc_ascii" == "1" ]]; then
      pass "mutant (line-framed, quoted) WRONGLY allows the non-ASCII push (rc=0) while still blocking the ASCII one (rc=1) — proves the encoding fix is load-bearing AND the mutant is discriminating"
    elif [[ "$rc" == "0" ]]; then
      fail "mutant allows the non-ASCII push but ALSO stopped blocking the ASCII golden case (rc=$rc_ascii) — the mutation is too broad to prove the encoding claim"
    else
      fail "mutant still blocked the non-ASCII push (rc=$rc) — the encoding mutation did not land, this scenario proves nothing"
    fi
  else
    fail "could not construct the encoding mutant (sed anchors not found — script drifted)"
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
