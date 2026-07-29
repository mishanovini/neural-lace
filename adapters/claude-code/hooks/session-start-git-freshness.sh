#!/bin/bash
# NEURAL-LACE-HOOK
# session-start-git-freshness.sh — SessionStart hook for git freshness.
#
# Surfaces four kinds of state at session start so the next session does
# not unknowingly work from a stale or conflicted starting point:
#
#   1. (Item 1) Local master behind a remote master. Fetches all remotes
#      (with a short timeout so a flaky network does not block session
#      start) and reports if any remote master has commits the local
#      master has not seen.
#
#   2. (Item 9) Working tree has uncommitted changes that are NOT on a
#      named WIP branch. Convention (per branch-hygiene rule): WIP work
#      lives on `wip/*`, `feat/*`, `fix/*`, `feature/*`, `bugfix/*`,
#      `salvage/*`, `backup/*`, or `rebase/*` branches. Uncommitted
#      changes on master or another "stable" branch are surprising and
#      worth warning about — they may indicate work from a previous
#      session that did not commit cleanly.
#
#   3. (Item 9 / convenience) Current branch + ahead/behind summary, so
#      the operator sees at a glance where they are.
#
#   4. (master-drift feed — docs/plans/master-drift-autocorrection-2026-07.md)
#      REMOTE-vs-REMOTE master drift: compares origin/master against the
#      mirror remote's master (the refs this hook already fetched — zero
#      extra network calls) and, on inequality OR a non-quiet status file,
#      dispatches scripts/master-drift-autocorrect.sh BACKGROUNDED (zero
#      blocking seconds; output to the corrector's own log). Renders the
#      corrector's status file (~/.claude/state/master-drift/<repo>.status)
#      as at most ONE digest line per session for the non-quiet states
#      (CORRECTED / DIVERGED / PUSH-REJECTED); CONVERGED/absent render
#      nothing. DIVERGED is never auto-merged — the line points at
#      docs/runbooks/master-drift-autocorrect.md (reviewed merge). Kill
#      switch: MASTER_DRIFT_AUTOCORRECT=0 skips dispatch entirely
#      (detection line still renders).
#
# Design notes:
# - Reads JSON on stdin per the SessionStart contract but ignores the
#   payload. The hook acts on the working directory.
# - Always exits 0 (informational; never blocks session start).
# - Silent if there is nothing to report.
# - Fast path: if not a git repo, exit 0 immediately.
# - Network fetch is timeout-bounded (default 10s) so the hook cannot
#   stall session start indefinitely on a slow/flaky link. The timeout
#   is honored as best-effort; on systems without `timeout` the fetch
#   runs unbounded.
#
# Self-test: invoke with --self-test to exercise the scenario matrix.

set -u

# ============================================================
# Constants
# ============================================================

FETCH_TIMEOUT_SECONDS="${FETCH_TIMEOUT_SECONDS:-10}"
# Branches where uncommitted work is expected and not worth flagging:
WIP_BRANCH_PATTERN='^(wip|feat|feature|fix|bugfix|salvage|backup|rebase|reconverge|sync)/'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
MD_RUNBOOK="docs/runbooks/master-drift-autocorrect.md"

# ============================================================
# Helpers
# ============================================================

_in_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

_remote_names() {
  git remote 2>/dev/null
}

_current_branch() {
  git symbolic-ref --short -q HEAD 2>/dev/null || echo ""
}

_has_uncommitted() {
  # Unstaged or staged changes (tracked files only — untracked are noise).
  ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null
}

_is_wip_branch() {
  local b="$1"
  [ -z "$b" ] && return 1
  printf '%s' "$b" | grep -qE "$WIP_BRANCH_PATTERN"
}

# Run git fetch --all with a best-effort timeout. Suppresses normal output;
# errors are echoed to stderr (the SessionStart layer ignores stderr but the
# operator can see them on direct invocation).
_safe_fetch_all() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$FETCH_TIMEOUT_SECONDS" git fetch --all --quiet 2>&1 | head -5 >&2 || return 0
  else
    git fetch --all --quiet 2>&1 | head -5 >&2 || return 0
  fi
}

# Echoes the count of commits on $1 that are not on $2 (i.e. how far $1 is
# AHEAD of $2). Empty string if either ref is missing.
_ahead_count() {
  local from="$1" to="$2"
  git rev-parse --verify --quiet "$from" >/dev/null || return 0
  git rev-parse --verify --quiet "$to" >/dev/null || return 0
  git rev-list --count "${to}..${from}" 2>/dev/null
}

# ============================================================
# master-drift feed helpers (item 4 in the header)
# ============================================================

# Status-dir resolution — MUST match master-drift-autocorrect.sh's
# _resolve_state_dir (same env override, same HARNESS_SELFTEST sandbox) so
# the hook reads exactly where the corrector writes.
_md_state_dir() {
  if [ -n "${MASTER_DRIFT_STATE_DIR:-}" ]; then
    printf '%s' "$MASTER_DRIFT_STATE_DIR"
  elif [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
    printf '%s' "${TMPDIR:-/tmp}/master-drift-state.selftest"
  else
    printf '%s' "${HOME}/.claude/state/master-drift"
  fi
}

# Corrector-log resolution — matches the corrector's _resolve_log_file so
# the backgrounded dispatch appends to the corrector's own log.
_md_log_file() {
  if [ -n "${MASTER_DRIFT_LOG_FILE:-}" ]; then
    printf '%s' "$MASTER_DRIFT_LOG_FILE"
  elif [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
    printf '%s' "${TMPDIR:-/tmp}/master-drift-autocorrect.selftest.log"
  else
    printf '%s' "${HOME}/.claude/logs/master-drift-autocorrect.log"
  fi
}

# Mirror remote discovery (read-only): first remote whose FETCH URL differs
# from origin's. Echoes the remote NAME or empty. FETCH urls deliberately
# (not push urls, unlike sync-pt-to-personal.sh's pattern): real checkouts
# here configure origin as a DUAL-PUSH remote whose first push url equals
# the mirror's, so push-URL comparison finds no mirror at all; what this
# feed compares are the remotes' FETCH identities (their remote-tracking
# master refs). Must match master-drift-autocorrect.sh's
# _discover_mirror_remote.
_md_mirror_remote() {
  local canonical_url name mirror_url
  canonical_url="$(git remote get-url origin 2>/dev/null || echo "")"
  [ -z "$canonical_url" ] && return 0
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    [ "$name" = "origin" ] && continue
    mirror_url="$(git remote get-url "$name" 2>/dev/null || echo "")"
    if [ -n "$mirror_url" ] && [ "$mirror_url" != "$canonical_url" ]; then
      printf '%s' "$name"
      return 0
    fi
  done < <(git remote 2>/dev/null)
}

# Backgrounded corrector dispatch: at most one per session start, zero
# blocking seconds (output to the corrector's own log; `&` + disown). The
# corrector self-discovers the repo from cwd — no arguments.
_md_dispatch_corrector() {
  local corrector log_file
  corrector="${MASTER_DRIFT_CORRECTOR:-$SCRIPT_DIR/../scripts/master-drift-autocorrect.sh}"
  [ -f "$corrector" ] || return 1
  log_file="$(_md_log_file)"
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
  nohup bash "$corrector" </dev/null >>"$log_file" 2>&1 &
  disown 2>/dev/null || true
  return 0
}

# The master-drift check (item 4): remote-vs-remote master comparison over
# refs ALREADY fetched by _safe_fetch_all (zero additional network calls),
# status-file rendering, and the backgrounded corrector dispatch. Appends to
# the caller's out_lines (bash dynamic scoping). Never blocks, never exits.
_md_check() {
  local toplevel repo_base mirror status_file status_line
  local origin_sha mirror_sha o7 m7 unequal=0 nonquiet=0

  toplevel="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
  [ -z "$toplevel" ] && return 0
  # Repo identity keys on the MAIN checkout, not an ephemeral linked worktree
  # (kept aligned with master-drift-autocorrect.sh, which skips linked-worktree
  # callers). In a linked worktree --git-common-dir points at the main .git.
  local _md_common _md_main_root
  _md_common="$(git rev-parse --git-common-dir 2>/dev/null || echo "")"
  case "$_md_common" in
    /*|[A-Za-z]:[\\/]*) : ;;
    "" ) _md_common="$toplevel/.git" ;;
    * ) _md_common="$toplevel/$_md_common" ;;
  esac
  _md_main_root="$(cd "$(dirname "$_md_common")" 2>/dev/null && pwd || echo "$toplevel")"
  repo_base="$(basename "$_md_main_root")"

  mirror="$(_md_mirror_remote)"

  # Remote-vs-remote comparison (only meaningful with a mirror remote and
  # both master refs present).
  if [ -n "$mirror" ]; then
    origin_sha="$(git rev-parse --verify --quiet origin/master 2>/dev/null || echo "")"
    mirror_sha="$(git rev-parse --verify --quiet "${mirror}/master" 2>/dev/null || echo "")"
    if [ -n "$origin_sha" ] && [ -n "$mirror_sha" ] && [ "$origin_sha" != "$mirror_sha" ]; then
      unequal=1
      o7="$(printf '%.7s' "$origin_sha")"; m7="$(printf '%.7s' "$mirror_sha")"
    fi
  fi

  # Status file from the corrector's LAST completed run — at most ONE line
  # rendered per session, non-quiet states only (CONVERGED/absent = quiet).
  status_file="$(_md_state_dir)/${repo_base}.status"
  status_line=""
  [ -f "$status_file" ] && status_line="$(head -n 1 "$status_file" 2>/dev/null)"
  case "$status_line" in
    CORRECTED\ *)
      set -- $status_line
      out_lines+=("[git-freshness] [master-drift] CORRECTED: ${2:-remote}/master fast-forwarded to ${3:-?}")
      nonquiet=1
      ;;
    DIVERGED\ *)
      set -- $status_line
      out_lines+=("[git-freshness] [master-drift] DIVERGED origin/master=${2:-?} ${mirror:-mirror}/master=${3:-?} — auto-sync refused; reviewed merge required (${MD_RUNBOOK})")
      nonquiet=1
      ;;
    PUSH-REJECTED\ *)
      set -- $status_line
      out_lines+=("[git-freshness] [master-drift] PUSH-REJECTED pushing ${2:-remote}/master (${3:-unknown}) — triage: ${MD_RUNBOOK}")
      nonquiet=1
      ;;
    *) : ;;  # CONVERGED, absent, or unparsable → quiet
  esac

  # Nothing to do (converged AND quiet status) → no dispatch, no lines.
  [ "$unequal" = "0" ] && [ "$nonquiet" = "0" ] && return 0

  # Kill switch: skip dispatch entirely; detection line still renders — but
  # ONLY when no non-quiet status line already rendered (else two lines per
  # session in the persistent diverged state — MAJOR-1).
  if [ "${MASTER_DRIFT_AUTOCORRECT:-1}" = "0" ]; then
    if [ "$unequal" = "1" ] && [ "$nonquiet" = "0" ]; then
      out_lines+=("[git-freshness] [master-drift] remote masters differ: origin/master=${o7} ${mirror}/master=${m7} — auto-correction disabled (MASTER_DRIFT_AUTOCORRECT=0)")
    fi
    return 0
  fi

  # Dispatch the corrector backgrounded: on SHA inequality (correct the
  # drift) OR on a non-quiet status with equal SHAs (re-evaluate so the
  # status returns to CONVERGED and the digest line retires).
  local dispatched="corrector dispatched (backgrounded)"
  _md_dispatch_corrector || dispatched="corrector missing — run: bash adapters/claude-code/install.sh"
  # Detection line ONLY when no non-quiet status line already rendered — in the
  # steady diverged/push-rejected state the status line already tells the story;
  # emitting both is the two-lines-per-session bug (MAJOR-1). Dispatch still
  # happens above regardless, so correction is not gated on the line.
  if [ "$unequal" = "1" ] && [ "$nonquiet" = "0" ]; then
    out_lines+=("[git-freshness] [master-drift] remote masters differ: origin/master=${o7} ${mirror}/master=${m7} — ${dispatched}")
  fi
  return 0
}

# ============================================================
# Main check
# ============================================================

_main_check() {
  local out_lines=()
  local current remote behind_count ahead_count

  _in_git_repo || return 0

  # 1. Fetch all remotes (best-effort, bounded).
  if [ -n "$(_remote_names)" ]; then
    _safe_fetch_all
  fi

  # 2. Local master vs remote masters — surface behind condition.
  if git rev-parse --verify --quiet master >/dev/null 2>&1; then
    while IFS= read -r remote; do
      [ -z "$remote" ] && continue
      git rev-parse --verify --quiet "${remote}/master" >/dev/null 2>&1 || continue
      behind_count="$(_ahead_count "${remote}/master" master)"
      ahead_count="$(_ahead_count master "${remote}/master")"
      if [ -n "$behind_count" ] && [ "$behind_count" -gt 0 ]; then
        if [ "$ahead_count" -gt 0 ]; then
          out_lines+=("[git-freshness] local master is BEHIND ${remote}/master by $behind_count commit(s) (and ahead by $ahead_count) — diverged. Reconcile before pushing.")
        else
          out_lines+=("[git-freshness] local master is BEHIND ${remote}/master by $behind_count commit(s). Run: git checkout master && git pull --ff-only ${remote} master")
        fi
      fi
    done < <(_remote_names)
  fi

  # 2.5. Remote-vs-remote master drift (item 4 in the header): comparison
  #      over the refs step 1 already fetched, status-file digest rendering,
  #      and the backgrounded master-drift-autocorrect.sh dispatch.
  _md_check

  # 3. Current branch state.
  current="$(_current_branch)"
  if [ -n "$current" ]; then
    if _has_uncommitted; then
      if [ "$current" = "master" ] || [ "$current" = "main" ]; then
        out_lines+=("[git-freshness] uncommitted changes on $current branch — this is unusual. Either commit on master (pre-customer policy), or branch off and commit there. See: git status")
      elif ! _is_wip_branch "$current"; then
        out_lines+=("[git-freshness] uncommitted changes on '$current' (not a recognized WIP branch). Expected WIP-branch patterns: wip/* feat/* fix/* feature/* bugfix/* salvage/* backup/* rebase/* reconverge/* sync/*. See: git status")
      fi
      # If on a WIP-pattern branch, uncommitted is expected → no warning.
    fi

    # Also surface ahead-of-master on a feature branch so the operator sees
    # at-a-glance "yes you have N commits to push" / "no, branch is fresh."
    if [ "$current" != "master" ] && [ "$current" != "main" ]; then
      if git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
        local feat_ahead feat_behind
        feat_ahead="$(_ahead_count "$current" origin/master)"
        feat_behind="$(_ahead_count origin/master "$current")"
        if [ -n "${feat_ahead:-}" ] && [ "$feat_ahead" -gt 0 ]; then
          if [ -n "${feat_behind:-}" ] && [ "$feat_behind" -gt 0 ]; then
            out_lines+=("[git-freshness] current branch '$current' is ahead of origin/master by $feat_ahead, behind by $feat_behind — consider merging origin/master into '$current' or rebasing carefully (push-friendly).")
          fi
        fi
      fi
    fi
  fi

  # 4. Emit. Silent if nothing to report.
  if [ "${#out_lines[@]}" -gt 0 ]; then
    printf '%s\n' "${out_lines[@]}"
  fi
}

# ============================================================
# Self-test
# ============================================================

_self_test() {
  local tmp pass=0 fail=0
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN
  echo "[self-test] tmpdir=$tmp"

  # Sandbox the master-drift feed for EVERY scenario (never read the real
  # ~/.claude/state, never dispatch the real corrector from a fixture): a
  # stub corrector records invocations to a log this suite asserts on.
  export HARNESS_SELFTEST=1
  export MASTER_DRIFT_STATE_DIR="$tmp/md-state"
  export MASTER_DRIFT_LOG_FILE="$tmp/md-corrector.log"
  export MASTER_DRIFT_CORRECTOR="$tmp/stub-corrector.sh"
  unset MASTER_DRIFT_AUTOCORRECT 2>/dev/null || true
  mkdir -p "$MASTER_DRIFT_STATE_DIR"
  printf '#!/bin/bash\necho "stub-invoked cwd=$(pwd)" >> "%s"\nexit 0\n' "$tmp/stub-invocations.log" > "$MASTER_DRIFT_CORRECTOR"

  # Wait (bounded) for the backgrounded stub dispatch to land.
  _md_stub_invoked() {
    local i=0
    while [ $i -lt 25 ]; do
      [ -s "$tmp/stub-invocations.log" ] && return 0
      sleep 0.2 2>/dev/null || sleep 1
      i=$((i+1))
    done
    return 1
  }

  # Reusable bare repo to act as origin
  ( cd "$tmp" && mkdir bare-canonical && cd bare-canonical && git init --bare --quiet )

  # T1: not a git repo → silent, exit 0
  (
    cd "$tmp"
    out="$(echo '{}' | _main_check)"
    if [ -z "$out" ]; then echo "  T1 not-a-git-repo silent: PASS"
    else echo "  T1 not-a-git-repo silent: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T2: git repo with no remotes → silent (no behind report; no current-branch warn unless dirty)
  (
    cd "$tmp" && mkdir noremote && cd noremote
    git init --quiet
    git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
    git config user.email "t@example.com" && git config user.name "T"
    echo a > a && git add a && git commit --quiet -m init
    out="$(_main_check 2>/dev/null)"
    if [ -z "$out" ]; then echo "  T2 no-remotes silent: PASS"
    else echo "  T2 no-remotes silent: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T3: local master is BEHIND origin/master → expect behind-warning
  (
    cd "$tmp" && mkdir behind && cd behind
    git init --quiet
    git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
    git config user.email "t@example.com" && git config user.name "T"
    git remote add origin "$tmp/bare-canonical"
    echo a > a && git add a && git commit --quiet -m init
    git push --quiet origin HEAD:master
    git branch master 2>/dev/null
    # Advance the remote master
    ( cd "$tmp" && mkdir advancer && cd advancer
      git init --quiet
      git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
      git config user.email "t@example.com" && git config user.name "T"
      git remote add origin "$tmp/bare-canonical"
      git fetch --quiet origin
      git checkout --quiet -b master origin/master
      echo b > b && git add b && git commit --quiet -m b
      git push --quiet origin master )
    # Local must be on master to compare master vs origin/master correctly.
    git fetch --quiet origin 2>/dev/null
    git checkout --quiet master 2>/dev/null || git checkout --quiet -b master
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "BEHIND origin/master"; then echo "  T3 behind-detection: PASS"
    else echo "  T3 behind-detection: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T4: local master matches origin/master → no behind warning
  (
    cd "$tmp/behind"
    git pull --ff-only --quiet origin master 2>/dev/null
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "BEHIND"; then echo "  T4 not-behind-when-current: FAIL (got: $out)"; return 1
    else echo "  T4 not-behind-when-current: PASS"; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T5: uncommitted changes on master → warn
  (
    cd "$tmp/behind"
    echo "uncommitted" > new-tracked.txt
    git add new-tracked.txt
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "uncommitted changes on master"; then echo "  T5 dirty-on-master warn: PASS"
    else echo "  T5 dirty-on-master warn: FAIL (got: $out)"; return 1; fi
    # reset for next scenario
    git reset --hard --quiet HEAD
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T6: uncommitted on a wip/* branch → silent
  (
    cd "$tmp/behind"
    git checkout --quiet -b wip/test-uncommit
    echo "uncommitted on wip" > wip.txt
    git add wip.txt
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "uncommitted changes"; then echo "  T6 dirty-on-wip-silent: FAIL (got: $out)"; return 1
    else echo "  T6 dirty-on-wip-silent: PASS"; fi
    git reset --hard --quiet HEAD && git checkout --quiet master && git branch -D wip/test-uncommit
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T7: uncommitted on an unrecognized branch (not master, not WIP-pattern) → warn
  (
    cd "$tmp/behind"
    git checkout --quiet -b random-junk
    echo "uncommitted" > junk.txt
    git add junk.txt
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q "not a recognized WIP branch"; then echo "  T7 dirty-on-unrecognized warn: PASS"
    else echo "  T7 dirty-on-unrecognized warn: FAIL (got: $out)"; return 1; fi
    git reset --hard --quiet HEAD && git checkout --quiet master && git branch -D random-junk
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T8: clean tree → silent
  (
    cd "$tmp/behind"
    out="$(_main_check 2>/dev/null)"
    if [ -z "$out" ]; then echo "  T8 clean-tree silent: PASS"
    else echo "  T8 clean-tree silent: FAIL (got: $out)"; return 1; fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # ---- master-drift feed scenarios (item 4 in the header) ----
  # Two-remote fixture: origin + a distinct-FETCH-URL mirror, initially
  # converged. origin is deliberately given the REAL checkouts' dual-push
  # shape (remote.origin.pushurl twice: mirror URL first, own URL second) —
  # push-URL-based discovery sees "same URL" and finds no mirror, which is
  # exactly the silent-no-op regression these scenarios must catch.
  ( cd "$tmp" && mkdir bare-md-origin bare-md-mirror \
      && git init --bare --quiet bare-md-origin && git init --bare --quiet bare-md-mirror \
      && mkdir mdrepo && cd mdrepo \
      && git init --quiet \
      && git config core.hooksPath "" \
      && git config user.email "t@example.com" && git config user.name "T" \
      && git remote add origin "$tmp/bare-md-origin" \
      && git config --add remote.origin.pushurl "$tmp/bare-md-mirror" \
      && git config --add remote.origin.pushurl "$tmp/bare-md-origin" \
      && git remote add acme-mirror "$tmp/bare-md-mirror" \
      && echo a > a && git add a && git commit --quiet -m init \
      && git push --quiet "$tmp/bare-md-origin" HEAD:master \
      && git push --quiet "$tmp/bare-md-mirror" HEAD:master \
      && git checkout --quiet master 2>/dev/null || git checkout --quiet -b master
  ) || { echo "  (md fixture setup FAIL)"; fail=$((fail+1)); }

  # T9: remote-vs-remote inequality → detection line renders AND the
  # corrector is dispatched (stub on MASTER_DRIFT_CORRECTOR records it).
  (
    # Advance ONLY the mirror bare (throwaway clone; no force pushes).
    ( cd "$tmp" && git clone --quiet bare-md-mirror md-advancer 2>/dev/null \
        && cd md-advancer && git config core.hooksPath "" \
        && git config user.email "t@example.com" && git config user.name "T" \
        && echo b > b && git add b && git commit --quiet -m adv \
        && git push --quiet origin HEAD:master ) && rm -rf "$tmp/md-advancer"
    cd "$tmp/mdrepo"
    git fetch --quiet origin 2>/dev/null; git fetch --quiet acme-mirror 2>/dev/null
    git pull --ff-only --quiet acme-mirror master 2>/dev/null || true  # keep LOCAL master current so only the remote-vs-remote line fires... (local==mirror, ahead of origin — behind-warning may still render for origin; tolerated)
    rm -f "$tmp/stub-invocations.log"
    out="$(_main_check 2>/dev/null)"
    if echo "$out" | grep -q '\[master-drift\] remote masters differ: origin/master=' \
       && echo "$out" | grep -q 'corrector dispatched (backgrounded)' \
       && _md_stub_invoked; then
      echo "  T9 remote-vs-remote inequality -> detection + dispatch: PASS"
    else
      echo "  T9 remote-vs-remote inequality -> detection + dispatch: FAIL (got: $out; stub=$(cat "$tmp/stub-invocations.log" 2>/dev/null))"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T9b (MAJOR-1): remotes UNEQUAL *and* a non-quiet DIVERGED status present →
  # STILL exactly ONE [master-drift] line (the status line), never two. This is
  # the persistent steady state the plan/manifest promise "≤1 line" for; pre-fix
  # it emitted the DIVERGED status line AND the "remote masters differ …
  # dispatched" detection line. Dispatch must still fire (fix suppresses the
  # duplicate LINE, not the correction).
  (
    cd "$tmp/mdrepo"
    printf 'DIVERGED abc1234 def5678\n' > "$MASTER_DRIFT_STATE_DIR/mdrepo.status"
    rm -f "$tmp/stub-invocations.log"
    out="$(_main_check 2>/dev/null)"
    count="$(echo "$out" | grep -c '\[master-drift\]')"
    if [ "$count" = "1" ] \
       && echo "$out" | grep -q '\[master-drift\] DIVERGED origin/master=abc1234' \
       && ! echo "$out" | grep -q 'remote masters differ' \
       && _md_stub_invoked; then
      echo "  T9b unequal+DIVERGED -> exactly ONE line (no duplicate), dispatch still fires: PASS"
    else
      echo "  T9b unequal+DIVERGED -> exactly ONE line: FAIL (count=$count got: $out)"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T14 (runs on the still-unequal fixture): kill switch skips dispatch but
  # keeps detection.
  (
    cd "$tmp/mdrepo"
    rm -f "$MASTER_DRIFT_STATE_DIR/mdrepo.status"   # quiet status: pure kill-switch case
    rm -f "$tmp/stub-invocations.log"
    out="$(MASTER_DRIFT_AUTOCORRECT=0 _main_check 2>/dev/null)"
    sleep 1
    if echo "$out" | grep -q '\[master-drift\] remote masters differ:.*auto-correction disabled (MASTER_DRIFT_AUTOCORRECT=0)' \
       && [ ! -s "$tmp/stub-invocations.log" ]; then
      echo "  T14 kill-switch -> detection kept, dispatch skipped: PASS"
    else
      echo "  T14 kill-switch -> detection kept, dispatch skipped: FAIL (got: $out; stub=$(cat "$tmp/stub-invocations.log" 2>/dev/null))"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # Reconverge the two bares for the status-rendering scenarios (plain FF
  # push of the mirror's tip to origin — no force).
  (
    cd "$tmp/mdrepo"
    git fetch --quiet acme-mirror 2>/dev/null
    git push --quiet origin "$(git rev-parse acme-mirror/master)":master 2>/dev/null
    git fetch --quiet origin 2>/dev/null
    [ "$(git rev-parse origin/master)" = "$(git rev-parse acme-mirror/master)" ]
  ) || { echo "  (md fixture reconverge FAIL)"; fail=$((fail+1)); }

  # T10: status DIVERGED → exactly ONE [master-drift] line naming both SHAs
  # and the runbook.
  (
    cd "$tmp/mdrepo"
    printf 'DIVERGED abc1234 def5678\n' > "$MASTER_DRIFT_STATE_DIR/mdrepo.status"
    out="$(_main_check 2>/dev/null)"
    count="$(echo "$out" | grep -c '\[master-drift\]')"
    if [ "$count" = "1" ] \
       && echo "$out" | grep -q '\[master-drift\] DIVERGED origin/master=abc1234 acme-mirror/master=def5678 — auto-sync refused; reviewed merge required (docs/runbooks/master-drift-autocorrect.md)'; then
      echo "  T10 status DIVERGED -> one digest line: PASS"
    else
      echo "  T10 status DIVERGED -> one digest line: FAIL (count=$count got: $out)"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T11: status CORRECTED → exactly ONE line; ALSO dispatches a
  # re-evaluation run (so the status can return to CONVERGED and retire).
  (
    cd "$tmp/mdrepo"
    printf 'CORRECTED acme-mirror abc1234\n' > "$MASTER_DRIFT_STATE_DIR/mdrepo.status"
    rm -f "$tmp/stub-invocations.log"
    out="$(_main_check 2>/dev/null)"
    count="$(echo "$out" | grep -c '\[master-drift\]')"
    if [ "$count" = "1" ] \
       && echo "$out" | grep -q '\[master-drift\] CORRECTED: acme-mirror/master fast-forwarded to abc1234' \
       && _md_stub_invoked; then
      echo "  T11 status CORRECTED -> one line + re-evaluation dispatch: PASS"
    else
      echo "  T11 status CORRECTED -> one line + re-evaluation dispatch: FAIL (count=$count got: $out)"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T12: status PUSH-REJECTED → exactly ONE line with the reason + runbook.
  (
    cd "$tmp/mdrepo"
    printf 'PUSH-REJECTED origin auth\n' > "$MASTER_DRIFT_STATE_DIR/mdrepo.status"
    out="$(_main_check 2>/dev/null)"
    count="$(echo "$out" | grep -c '\[master-drift\]')"
    if [ "$count" = "1" ] \
       && echo "$out" | grep -q '\[master-drift\] PUSH-REJECTED pushing origin/master (auth) — triage: docs/runbooks/master-drift-autocorrect.md'; then
      echo "  T12 status PUSH-REJECTED -> one digest line: PASS"
    else
      echo "  T12 status PUSH-REJECTED -> one digest line: FAIL (count=$count got: $out)"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  # T13: status CONVERGED (and equal remotes) → ZERO master-drift lines and
  # no dispatch.
  (
    cd "$tmp/mdrepo"
    printf 'CONVERGED abc1234\n' > "$MASTER_DRIFT_STATE_DIR/mdrepo.status"
    rm -f "$tmp/stub-invocations.log"
    out="$(_main_check 2>/dev/null)"
    sleep 1
    if ! echo "$out" | grep -q '\[master-drift\]' && [ ! -s "$tmp/stub-invocations.log" ]; then
      echo "  T13 status CONVERGED -> zero lines, no dispatch: PASS"
    else
      echo "  T13 status CONVERGED -> zero lines, no dispatch: FAIL (got: $out; stub=$(cat "$tmp/stub-invocations.log" 2>/dev/null))"
      return 1
    fi
  ) && pass=$((pass+1)) || fail=$((fail+1))

  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return $fail
}

# ============================================================
# Entry point
# ============================================================

case "${1:-}" in
  --self-test)
    _self_test
    exit $?
    ;;
  *)
    # SessionStart hooks receive a JSON payload on stdin; we ignore it.
    cat >/dev/null 2>&1 || true
    _main_check
    exit 0
    ;;
esac
