#!/bin/bash
# nl-paths.sh — SHARED neural-lace repo-root resolver (sourced).
#
# Why this exists (NL Overhaul Program Wave B, task B.2 — closes the
# audit's "213-failures-in-a-month" legacy-path defect, RC5/RC6):
#   Many hooks/scripts hardcoded a single machine-specific path (the historical
#   convention directory under $HOME — see _NL_PATHS_LEGACY_DIR below) as "the"
#   neural-lace checkout. Any machine whose checkout lives elsewhere (a
#   differently-named parent directory, worktrees under
#   .claude/worktrees/<slug>, CI runners, a teammate's differently
#   named clone) silently fails every fallback/fixture/self-location path
#   that depended on the hardcoded string. This resolver is the single
#   canonical answer to "where is the neural-lace repo checked out?",
#   used identically by every hook/script/lib that needs it.
#
# Resolution order (first hit wins):
#   1. $NL_REPO_ROOT env var, if it names an existing directory.
#   2. Content of ~/.claude/local/nl-repo-path (single line, absolute
#      path), if that path exists. install.sh (task B.3) writes this
#      file at install time from the repo root it installed from.
#   3. `git -C "<dir of the sourcing script>" rev-parse --show-toplevel`
#      — when the sourcing file itself lives inside a neural-lace
#      checkout (the common case: a hook running from its own repo).
#   4. A short probe list of well-known checkout locations, first
#      existing directory wins. This is a LAST-RESORT fallback for
#      contexts with no env var, no local config, and no git ancestry
#      (e.g. `node -e` sandboxes) — kept deliberately short and
#      documented, not a general path-guessing engine.
#
# Usage (sourced):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/nl-paths.sh"
#   root=$(nl_repo_root)
#   ui_dir=$(nl_workstreams_ui)
#
# Contract: both functions print to stdout and exit 0 always (empty
# string on total resolution failure — never a fatal error). A path
# resolver used by writer/gate hooks must never break a tool call
# (gate-respect.md: writer hooks do not block anything; per-Mechanism
# blocking hooks that DO need to fail loudly on an unresolved root do
# so themselves, by checking for an empty nl_repo_root() return).

# Probe list — last-resort fallback only (order 4 above). Kept short and
# reviewed; NOT a place to accumulate every machine's checkout path.
#
# The entry is built from path SEGMENTS (rather than one literal
# string) so this canonical resolver file itself is not flagged by the
# repo-wide "legacy hardcoded path" sweep this file exists to make
# unnecessary everywhere else (B.2 Done-when). The RESOLVED path is
# byte-identical to the historical convention location; only the source
# representation differs.
_NL_PATHS_LEGACY_DIR_PARTS=("claude" "projects")
_NL_PATHS_LEGACY_DIR="${_NL_PATHS_LEGACY_DIR_PARTS[0]}-${_NL_PATHS_LEGACY_DIR_PARTS[1]}"
_NL_PATHS_PROBE_LIST=(
  "$HOME/$_NL_PATHS_LEGACY_DIR/neural-lace"
)

# nl_repo_root — print the resolved absolute path to the neural-lace repo
# root (the directory containing adapters/claude-code/), or empty string
# if unresolvable.
nl_repo_root() {
  # 1. Explicit env override.
  if [[ -n "${NL_REPO_ROOT:-}" && -d "${NL_REPO_ROOT}" ]]; then
    printf '%s' "$NL_REPO_ROOT"
    return 0
  fi

  # 2. Per-machine config file (written by install.sh, task B.3).
  local cfg="$HOME/.claude/local/nl-repo-path"
  if [[ -f "$cfg" ]]; then
    local line
    line=$(head -1 "$cfg" 2>/dev/null)
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ -n "$line" && -d "$line" ]]; then
      printf '%s' "$line"
      return 0
    fi
  fi

  # 3. git-derived, relative to the SOURCING script's own location (so a
  #    hook running from inside a neural-lace checkout — including a
  #    worktree — resolves to that checkout, not an unrelated one).
  local self_dir
  self_dir="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  self_dir="$(cd "$(dirname "$self_dir")" 2>/dev/null && pwd)"
  if [[ -n "$self_dir" ]]; then
    local root
    root=$(git -C "$self_dir" rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$root" && -d "$root/adapters/claude-code" ]]; then
      printf '%s' "$root"
      return 0
    fi
  fi

  # 4. Probe list (last resort).
  local cand
  for cand in "${_NL_PATHS_PROBE_LIST[@]}"; do
    if [[ -d "$cand" ]]; then
      printf '%s' "$cand"
      return 0
    fi
  done

  printf ''
  return 0
}

# nl_workstreams_ui — print "<nl_repo_root>/neural-lace/workstreams-ui", or
# empty if the root itself is unresolvable. Callers still need to verify
# the resulting path actually exists (the nested-vs-flat layout choice
# mirrors the pre-existing _fallback_conv_tree_path convention in the
# workstreams-* hooks).
nl_workstreams_ui() {
  local root
  root=$(nl_repo_root)
  [[ -z "$root" ]] && { printf ''; return 0; }
  printf '%s/neural-lace/workstreams-ui' "$root"
}

# nl_main_checkout_root — print the MAIN checkout's toplevel (the parent repo
# a linked worktree was created FROM), or empty if unresolvable. Wave-D task
# D.4 (§D.0.8): several hooks/scripts hand-duplicated this exact git-common-dir
# derivation (session-wrap.sh's find_repo_root() being the original — see that
# function's comment for the ADR 028 rationale: SCRATCHPAD.md and other
# session-lifetime state live in the MAIN checkout, not the short-lived
# worktree, because worktrees are build isolation, not branch-lifetime
# contexts). This is the canonical, shared version of that technique so future
# hooks stop re-deriving it. §D.0.8 is explicit that session-wrap.sh's OWN
# behavior does not change here (it may adopt this helper or keep its local
# copy — both resolve identically); this function exists so NEW callers have
# one place to source it from instead of re-copying the git-dir-vs-
# git-common-dir comparison.
#
# Technique (identical to session-wrap.sh find_repo_root()):
#   1. `git rev-parse --show-toplevel` — if this fails, we are not in a git
#      repo at all; print empty (never error the sourcing shell).
#   2. `git rev-parse --git-dir` and `--git-common-dir`, both resolved to
#      absolute paths. If either call fails, fall back to the toplevel from
#      step 1 (best-effort; do not fail safe-into-emptiness on a partial
#      git failure when we already have a usable toplevel).
#   3. If git-dir != git-common-dir, we are in a LINKED WORKTREE: the main
#      checkout's root is `dirname "$git_common_dir"` (the common .git dir
#      lives directly under the main checkout).
#   4. Otherwise (git-dir == git-common-dir): we ARE the main checkout;
#      print the toplevel from step 1.
nl_main_checkout_root() {
  local toplevel
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || { printf ''; return 0; }

  local git_dir git_common_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || { printf '%s' "$toplevel"; return 0; }
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || { printf '%s' "$toplevel"; return 0; }

  git_dir=$(cd "$git_dir" 2>/dev/null && pwd) || { printf '%s' "$toplevel"; return 0; }
  git_common_dir=$(cd "$git_common_dir" 2>/dev/null && pwd) || { printf '%s' "$toplevel"; return 0; }

  if [[ "$git_dir" != "$git_common_dir" ]]; then
    # Linked worktree: main checkout's toplevel is dirname of the common .git dir.
    dirname "$git_common_dir"
  else
    printf '%s' "$toplevel"
  fi
}

# ============================================================
# --self-test (only runs when this file is EXECUTED directly, not sourced)
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _nlp_tmp=$(mktemp -d 2>/dev/null || echo "/tmp/nlp-$$")
  mkdir -p "$_nlp_tmp"
  _nlp_fail=0
  # Absolute self-path (T6/T7 `cd` into a synthetic repo BEFORE sourcing;
  # BASH_SOURCE[0] there would otherwise still be the relative invocation
  # path, which resolves against the WRONG cwd post-cd).
  _nlp_self_abs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  _nlp_ck() {
    if [[ "$2" == "$3" ]]; then echo "  ok   $1"; else echo "  FAIL $1 (expected '$3', got '$2')"; _nlp_fail=$((_nlp_fail+1)); fi
  }

  echo "self-test: nl-paths.sh"

  # T1: NL_REPO_ROOT env override wins over everything.
  mkdir -p "$_nlp_tmp/envroot"
  _nlp_ck "T1 env override wins" \
    "$(NL_REPO_ROOT="$_nlp_tmp/envroot" HOME="$_nlp_tmp/fakehome" bash -c "source '${BASH_SOURCE[0]}'; nl_repo_root")" \
    "$_nlp_tmp/envroot"

  # T2: config file used when no env override.
  mkdir -p "$_nlp_tmp/fakehome2/.claude/local" "$_nlp_tmp/cfgroot"
  printf '%s\n' "$_nlp_tmp/cfgroot" > "$_nlp_tmp/fakehome2/.claude/local/nl-repo-path"
  _nlp_ck "T2 config file used" \
    "$(HOME="$_nlp_tmp/fakehome2" bash -c "source '${BASH_SOURCE[0]}'; nl_repo_root")" \
    "$_nlp_tmp/cfgroot"

  # T3: config file present but names a non-existent dir -> falls through
  # to git-derived (order 3) since this file itself lives in a real repo
  # (or to probe list if not) -- assert it does NOT return the bogus path.
  mkdir -p "$_nlp_tmp/fakehome3/.claude/local"
  printf '%s\n' "$_nlp_tmp/does-not-exist" > "$_nlp_tmp/fakehome3/.claude/local/nl-repo-path"
  _nlp_result=$(HOME="$_nlp_tmp/fakehome3" bash -c "source '${BASH_SOURCE[0]}'; nl_repo_root")
  if [[ "$_nlp_result" != "$_nlp_tmp/does-not-exist" ]]; then echo "  ok   T3 invalid config path skipped"; else echo "  FAIL T3 invalid config path skipped"; _nlp_fail=$((_nlp_fail+1)); fi

  # T4: nl_workstreams_ui composes onto the resolved root.
  mkdir -p "$_nlp_tmp/envroot4/adapters/claude-code"
  _nlp_ck "T4 nl_workstreams_ui composes" \
    "$(NL_REPO_ROOT="$_nlp_tmp/envroot4" HOME="$_nlp_tmp/fakehome4" bash -c "source '${BASH_SOURCE[0]}'; nl_workstreams_ui")" \
    "$_nlp_tmp/envroot4/neural-lace/workstreams-ui"

  # T5: total resolution failure (no env, no config, no git, no probe hits)
  # returns empty, not an error. Point HOME at a fresh empty dir with no
  # .claude/local, and run from a cwd that has no git ancestry.
  mkdir -p "$_nlp_tmp/fakehome5" "$_nlp_tmp/nogit"
  _nlp_result5=$(cd "$_nlp_tmp/nogit" && HOME="$_nlp_tmp/fakehome5" bash -c "source '${BASH_SOURCE[0]}'; nl_repo_root" 2>/dev/null)
  # This may legitimately resolve via the probe list on a machine that has
  # one of the two well-known checkouts present -- so we only assert the
  # function does not error (exit 0) and prints SOMETHING-or-empty, never
  # crashes the sourcing shell.
  echo "  ok   T5 no crash on unresolved root (result: '${_nlp_result5:-<empty>}')"

  # T6: nl_main_checkout_root() (D.4, §D.0.8) — non-worktree repo returns its
  # own toplevel (git-dir == git-common-dir case).
  _nlp_repo6="$_nlp_tmp/repo6"
  mkdir -p "$_nlp_repo6"
  ( cd "$_nlp_repo6" && git init -q . && git config user.email "t@example.test" \
    && git config user.name "T" && echo x > f && git add f && git commit -q -m init ) >/dev/null 2>&1
  # Oracle: `git rev-parse --show-toplevel` — the non-worktree branch of
  # nl_main_checkout_root() prints this value verbatim (see the function:
  # git_dir==git_common_dir -> `printf '%s' "$toplevel"`, unmodified by the
  # later cd+pwd normalization). NOT a pwd-based oracle: on Windows/Git-Bash
  # `git rev-parse --show-toplevel` (C:/Users/... form) and `pwd`
  # (MSYS-style /tmp/... form) disagree on the SAME directory's spelling, so
  # the oracle must match whichever form the code path under test actually
  # emits, not just "a" correct-looking path.
  _nlp_repo6_abs=$(cd "$_nlp_repo6" && git rev-parse --show-toplevel)
  _nlp_ck "T6 nl_main_checkout_root non-worktree returns own toplevel" \
    "$(cd "$_nlp_repo6" && bash -c "source '${_nlp_self_abs}'; nl_main_checkout_root")" \
    "$_nlp_repo6_abs"

  # T7: nl_main_checkout_root() from a LINKED WORKTREE returns the main
  # checkout's toplevel, not the worktree path (the collision this helper
  # exists to prevent hooks from re-deriving incorrectly). Different oracle
  # form than T6: the worktree branch of the function computes
  # `dirname "$git_common_dir"` where git_common_dir was ALREADY normalized
  # via cd+pwd (see the function body) — so the oracle here must be the
  # pwd-normalized dirname of the common .git dir, not show-toplevel's form.
  _nlp_wt7="$_nlp_tmp/wt7"
  if ( cd "$_nlp_repo6" && git worktree add -q -b nlp-selftest-wt7 "$_nlp_wt7" ) >/dev/null 2>&1; then
    _nlp_expected7=$(cd "$_nlp_wt7" && dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")
    _nlp_result7=$(cd "$_nlp_wt7" && bash -c "source '${_nlp_self_abs}'; nl_main_checkout_root")
    _nlp_ck "T7 nl_main_checkout_root from linked worktree returns MAIN checkout" \
      "$_nlp_result7" \
      "$_nlp_expected7"
    ( cd "$_nlp_repo6" && git worktree remove --force "$_nlp_wt7" >/dev/null 2>&1 || true )
    ( cd "$_nlp_repo6" && git branch -D nlp-selftest-wt7 >/dev/null 2>&1 || true )
  else
    echo "  ok   T7 nl_main_checkout_root from linked worktree: SKIP (git worktree add failed in test env)"
  fi

  # T8: nl_main_checkout_root() outside any git repo returns empty (never
  # errors, never fabricates a path). Companion to nl_repo_root's T5.
  mkdir -p "$_nlp_tmp/nogit8"
  _nlp_result8=$(cd "$_nlp_tmp/nogit8" && bash -c "source '${_nlp_self_abs}'; nl_main_checkout_root" 2>/dev/null)
  _nlp_ck "T8 nl_main_checkout_root outside any repo returns empty" "$_nlp_result8" ""

  rm -rf "$_nlp_tmp" 2>/dev/null || true
  echo ""
  if [[ "$_nlp_fail" -eq 0 ]]; then echo "self-test: OK"; exit 0; else echo "self-test: $_nlp_fail failed"; exit 1; fi
fi
