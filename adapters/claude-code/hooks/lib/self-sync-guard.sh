# self-sync-guard.sh — shared library: detect a sync whose source and
# target are the SAME object on disk (SELF-SYNC-01, 2026-07-29).
#
# ============================================================
# WHAT THIS PREVENTS (proven data loss, twice in ten minutes on 2026-07-29)
# ============================================================
#
# On a SYMLINK-based install, a live ~/.claude/ entry (e.g. hooks/) is a
# symlink back into this repo's adapters/claude-code/. Any installer that
# then does `rm -rf $target && copy $source -> $target` (or a diff+overwrite
# of $target with older reference content) can find that $target resolves,
# THROUGH the symlink, onto $source itself -- deleting or reverting the very
# tree it meant to read from. install.sh's `rm -rf "$dst"` destroyed 19 files
# / ~12,400 lines of hooks/lib/ (admission-lib.sh among them) this way.
# session-start-auto-install.sh hit the same root cause through its own
# code path: it overwrote 27 files of committed-but-not-yet-on-origin/master
# branch work with older origin/master content, because the live path it
# was "updating" WAS the repo's own working-tree file, reached through a
# symlinked ~/.claude/hooks.
#
# ============================================================
# WHO ACTUALLY SHARES THIS FILE (corrected 2026-07-30 -- see below)
# ============================================================
#
# resolve_real_path() below is hand-rolled (stock macOS has no `realpath`
# and no `readlink -f`) and took real engineering effort to get right across
# symlinked parents, symlinked leaves, `..`, trailing slashes, relative
# input, and targets that do not exist yet (12 scenarios in
# tests/install-self-sync-guard-test.sh). Two independent copies of this
# logic WILL drift the next time one of them gets a bugfix the other
# doesn't -- and that is the state TODAY, not a hypothetical:
#
#   - session-start-auto-install.sh DOES source this file (`source
#     .../lib/self-sync-guard.sh`, with an inert always-different-paths
#     stub if the source fails -- see that file's own header) for the
#     detection primitives (`resolve_real_path`, `_sync_self_check`,
#     `_resolves_into_dir`).
#   - install.sh does NOT source this file. It carries its OWN, independent
#     inline copy of resolve_real_path / _sync_self_check /
#     _resolves_into_adapter_dir (install.sh, defined before any MODE
#     branch, ~lines 290-411) -- this file's predecessor, written a few
#     hours earlier the same day (4e29dc6) and never retrofitted. The two
#     copies have ALREADY drifted in their comments (install.sh's
#     resolve_real_path docstring adds "This is what makes a not-yet-created
#     target comparable at all," a line this file's copy never had) -- the
#     leading indicator of the logic itself drifting next, which is exactly
#     what the drift-pinning self-test scenario below now watches for.
#
# WHY install.sh was never retrofitted onto this shared file (PROVEN, not
# guessed -- see docs/decisions/065-self-sync-guard-signal-level.md
# "Related, NOT done here" and docs/backlog.md's
# SELF-SYNC-GUARD-INSTALLSH-RETROFIT-01): when this file was extracted for
# session-start-auto-install.sh's use, install.sh's inline copy was hours
# old and already proven (12/12 on both bash interpreters) as the emergency
# fix for a real data-loss incident, and that session was expressly
# forbidden from running install.sh itself (it was the very script that had
# just destroyed 19 files) -- removing the most direct way to confirm a
# refactor of it didn't regress its own end-to-end flow. Leaving a
# known-good emergency fix alone was judged lower-risk than refactoring it
# without the ability to smoke-test the result, so the retrofit was filed as
# a follow-up instead of bundled in. It remains open as of this correction;
# per this review sweep's orchestrator, the review-queue/runner ("RI")
# pipeline currently being built in a concurrent session is the intended
# landing spot for install.sh's broader restructure, so full convergence is
# deferred to that work rather than attempted piecemeal here -- tracked, not
# silently dropped, and the drift-pinning scenario below fails LOUDLY the
# moment the two copies' actual behavior (not just their comments) diverges.
#
# What is deliberately NOT shared, independent of the above: each carrier's
# PRESENTATION of a detected self-sync. install.sh is operator-present (a
# human is watching stdout in real time), so its `sync_is_self_sync()`
# prints a full explanatory block per call and that stays local to
# install.sh. session-start-auto-install.sh runs unattended on every
# SessionStart and would emit that same block on EVERY file, EVERY session,
# forever on a symlinked-install machine -- so it aggregates into a counter
# folded into its one-line-per-run summary instead (see
# session-start-auto-install.sh header for the full skip-vs-louder
# reasoning). The DETECTION primitives are what this file is about; the
# reporting is intentionally carrier-specific either way.
#
# ============================================================
# PORTABILITY
# ============================================================
# bash 3.2.57 (stock macOS) and 5.x alike. No arrays, no `local -n`, no
# process substitution in a way that breaks 3.2, no GNU-only flags, no
# `realpath`, no `readlink -f`.

# Print the PHYSICAL (fully symlink-resolved) absolute path of $1 on stdout.
#
# Handles symlinks anywhere in the path (including a symlinked PARENT with a
# real leaf -- the topology that caused the loss), `..` components, trailing
# slashes, relative input, and a path that DOES NOT EXIST YET (resolve the
# deepest existing ancestor, re-append the missing tail).
#
# Portability: stock macOS has no `realpath` and its `readlink` has no -f, so
# `cd ... && pwd -P` is the only universally available idiom.
resolve_real_path() {
  local p="$1"
  local tail="" dir base rdir link
  local depth=0

  [ -n "$p" ] || return 1
  # Make relative input absolute before any resolution.
  case "$p" in
    /*) : ;;
    *)  p="$PWD/$p" ;;
  esac
  # Strip trailing slashes ("/foo/" and "/foo///" == "/foo"; bare "/" stays).
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done

  # Anything that exists as a directory: `cd` follows every symlink in the
  # chain (leaf AND ancestors) and `pwd -P` prints the physical answer, which
  # also collapses any `..` components.
  if [ -d "$p" ]; then
    (cd "$p" 2>/dev/null && pwd -P) || return 1
    return 0
  fi

  # A symlink to a FILE (or a dangling symlink): `cd` cannot help, so follow
  # the link chain by hand. Bounded at 40 hops so a symlink cycle terminates
  # instead of hanging the caller.
  while [ -L "$p" ] && [ "$depth" -lt 40 ]; do
    link="$(readlink "$p" 2>/dev/null)" || break
    [ -n "$link" ] || break
    case "$link" in
      /*) p="$link" ;;
      *)  dir="${p%/*}"
          if [ -z "$dir" ] || [ "$dir" = "$p" ]; then dir="/"; fi
          p="$dir/$link" ;;
    esac
    while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
    depth=$((depth + 1))
    if [ -d "$p" ]; then
      (cd "$p" 2>/dev/null && pwd -P) || return 1
      return 0
    fi
  done

  # A plain file, or a path that does not exist yet: peel leaf components
  # until an existing directory is found, resolve THAT physically, and
  # re-append what was peeled.
  while :; do
    base="${p##*/}"
    dir="${p%/*}"
    if [ -z "$dir" ]; then dir="/"; fi
    if [ -n "$tail" ]; then tail="$base/$tail"; else tail="$base"; fi
    if [ -d "$dir" ]; then
      rdir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
      if [ "$rdir" = "/" ]; then
        printf '/%s\n' "$tail"
      else
        printf '%s/%s\n' "$rdir" "$tail"
      fi
      return 0
    fi
    if [ "$dir" = "/" ]; then
      printf '/%s\n' "$tail"
      return 0
    fi
    p="$dir"
  done
}

# Returns 0 (and prints the shared physical path) when $1 and $2 are the
# SAME object on disk; returns 1 (the normal, different-paths case)
# otherwise. Deliberately fails CLOSED as "not the same" if either side
# cannot be resolved, so an unresolvable path can never silently suppress a
# legitimate sync.
_sync_self_check() {
  local src_real dst_real
  src_real="$(resolve_real_path "$1" 2>/dev/null)" || return 1
  dst_real="$(resolve_real_path "$2" 2>/dev/null)" || return 1
  [ -n "$src_real" ] || return 1
  [ -n "$dst_real" ] || return 1
  [ "$src_real" = "$dst_real" ] || return 1
  printf '%s\n' "$src_real"
  return 0
}

# Returns 0 when $1 resolves to a path INSIDE (or equal to) directory $2 --
# i.e. a "live" path that is really a repo file reached through a symlink.
# Generalizes install.sh's `_resolves_into_adapter_dir` (which hardcoded
# $ADAPTER_DIR) so both carriers can guard a prune/delete step against
# deleting a repo file through a symlinked live path, whatever their own
# notion of "the repo directory" is.
_resolves_into_dir() {
  local p_real container_real
  p_real="$(resolve_real_path "$1" 2>/dev/null)" || return 1
  container_real="$(resolve_real_path "$2" 2>/dev/null)" || return 1
  [ -n "$p_real" ] || return 1
  [ -n "$container_real" ] || return 1
  case "$p_real" in
    "$container_real"|"$container_real"/*) return 0 ;;
  esac
  return 1
}

# ----------------------------------------------------------------------
# --self-test
# ----------------------------------------------------------------------
# Usage: bash adapters/claude-code/hooks/lib/self-sync-guard.sh --self-test
#
# Covers this file's own primitives (baseline) plus the DRIFT-PINNING
# scenario (2026-07-30): install.sh does NOT source this file (see header
# above) -- it carries its own independent inline copy of
# resolve_real_path/_sync_self_check, which can silently drift from this
# file's version. This scenario extracts install.sh's REAL function bodies
# at run time (no forked copy that could itself drift), renames them so
# they cannot clobber this file's own already-loaded functions of the same
# name, and asserts IDENTICAL verdicts on a shared fixture table of
# path-pairs. A behavioral divergence between the two copies goes RED here
# -- without the two ever sharing a line of implementation.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0; FAILED=0
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t ssgst)
  trap 'rm -rf "$TMP"' EXIT

  ok() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  no() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  # ---- baseline: this file's OWN primitives behave as documented ----
  mkdir -p "$TMP/real/sub"
  ln -s "$TMP/real" "$TMP/link"
  WANT="$(cd "$TMP/real/sub" && pwd -P)"
  [ "$(resolve_real_path "$TMP/real/sub")" = "$WANT" ] \
    && ok "resolve_real_path: plain path" || no "resolve_real_path: plain path"
  [ "$(resolve_real_path "$TMP/link/sub")" = "$WANT" ] \
    && ok "resolve_real_path: via symlinked parent" || no "resolve_real_path: via symlinked parent"

  mkdir -p "$TMP/a"
  ln -s "$TMP/a" "$TMP/b-link"
  _sync_self_check "$TMP/a" "$TMP/b-link" >/dev/null 2>&1 \
    && ok "_sync_self_check: same object (via symlink) detected" \
    || no "_sync_self_check: same object (via symlink) detected"
  mkdir -p "$TMP/c" "$TMP/d"
  if _sync_self_check "$TMP/c" "$TMP/d" >/dev/null 2>&1; then
    no "_sync_self_check: falsely flagged different directories as the same object"
  else
    ok "_sync_self_check: genuinely different directories -> not same"
  fi

  # ---- DRIFT-PINNING: install.sh's INDEPENDENT inline copy must agree ----
  SSG_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  SSG_LIB_DIR="$(dirname "$SSG_SELF")"
  INSTALL_SH="${INSTALL_SH_UNDER_TEST:-$SSG_LIB_DIR/../../install.sh}"
  if [ ! -f "$INSTALL_SH" ]; then
    no "drift-pinning: install.sh not found at $INSTALL_SH -- scenario could not run"
  else
    INSTALL_FUNCS="$TMP/install-funcs.sh"
    {
      awk '/^resolve_real_path\(\) \{/{f=1} f{print} /^\}$/{if(f){f=0;exit}}' "$INSTALL_SH"
      awk '/^_sync_self_check\(\) \{/{f=1} f{print} /^\}$/{if(f){f=0;exit}}' "$INSTALL_SH"
    } | sed \
        -e 's/^resolve_real_path()/_isg_install_resolve_real_path()/' \
        -e 's/^_sync_self_check()/_isg_install_sync_self_check()/' \
        -e 's/resolve_real_path "/_isg_install_resolve_real_path "/g' \
        > "$INSTALL_FUNCS"

    if ! grep -q '^_isg_install_resolve_real_path()' "$INSTALL_FUNCS" \
       || ! grep -q '^_isg_install_sync_self_check()' "$INSTALL_FUNCS"; then
      no "drift-pinning: could not extract resolve_real_path/_sync_self_check from $INSTALL_SH (extraction shape changed?)"
    else
      # shellcheck disable=SC1090
      . "$INSTALL_FUNCS"
      if ! declare -F _isg_install_sync_self_check >/dev/null 2>&1; then
        no "drift-pinning: extracted install.sh copy did not define after sourcing"
      else
        # Fixture builders: each sets _DC_A/_DC_B (the src/dst pair) for one topology.
        _build_symlinked_parent() {
          local d="$TMP/dp-parent"; rm -rf "$d"; mkdir -p "$d/repo/hooks/lib" "$d/home/.claude"
          ln -s "$d/repo/hooks" "$d/home/.claude/hooks"
          _DC_A="$d/repo/hooks/lib"; _DC_B="$d/home/.claude/hooks/lib"
        }
        _build_different_dirs() {
          local d="$TMP/dp-diff"; rm -rf "$d"; mkdir -p "$d/a" "$d/b"
          _DC_A="$d/a"; _DC_B="$d/b"
        }
        _build_target_symlink_to_source_file() {
          local d="$TMP/dp-file"; rm -rf "$d"; mkdir -p "$d/repo" "$d/home"
          printf 'x\n' > "$d/repo/manifest.json"
          ln -s "$d/repo/manifest.json" "$d/home/manifest.json"
          _DC_A="$d/repo/manifest.json"; _DC_B="$d/home/manifest.json"
        }
        _build_dangling_target() {
          local d="$TMP/dp-dangling"; rm -rf "$d"; mkdir -p "$d/repo"
          printf 'x\n' > "$d/repo/manifest.json"
          ln -s "$d/nowhere/gone.json" "$d/dangling.json"
          _DC_A="$d/repo/manifest.json"; _DC_B="$d/dangling.json"
        }
        _build_third_party_symlinks() {
          local d="$TMP/dp-third"; rm -rf "$d"; mkdir -p "$d/third/hooks" "$d/repo" "$d/home/.claude"
          ln -s "$d/third/hooks" "$d/repo/hooks"
          ln -s "$d/third/hooks" "$d/home/.claude/hooks"
          _DC_A="$d/repo/hooks"; _DC_B="$d/home/.claude/hooks"
        }

        # <label> <build-fn> <expect: same|diff>
        _drift_case() {
          local label="$1" build="$2" expect="$3" lib_rc inst_rc
          "$build"
          _sync_self_check "$_DC_A" "$_DC_B" >/dev/null 2>&1; lib_rc=$?
          _isg_install_sync_self_check "$_DC_A" "$_DC_B" >/dev/null 2>&1; inst_rc=$?
          if [ "$lib_rc" -ne "$inst_rc" ]; then
            no "drift-pinning ($label): DRIFT -- lib rc=$lib_rc, install.sh's inline copy rc=$inst_rc"
            return
          fi
          if [ "$expect" = "same" ] && [ "$lib_rc" -ne 0 ]; then
            no "drift-pinning ($label): both copies agree, but neither detected the self-sync (rc=$lib_rc, expected 0)"
            return
          fi
          if [ "$expect" = "diff" ] && [ "$lib_rc" -eq 0 ]; then
            no "drift-pinning ($label): both copies agree, but falsely flagged different paths as the same object"
            return
          fi
          ok "drift-pinning ($label): lib and install.sh's inline copy agree (rc=$lib_rc)"
        }

        _drift_case "symlinked parent, same leaf (the production bug shape)" _build_symlinked_parent same
        _drift_case "genuinely different directories" _build_different_dirs diff
        _drift_case "target symlink -> source file" _build_target_symlink_to_source_file same
        _drift_case "dangling target symlink" _build_dangling_target diff
        _drift_case "both sides symlink to a third directory" _build_third_party_symlinks same
      fi
    fi
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  [[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
fi
