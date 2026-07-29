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
# WHY ONE SHARED FILE, NOT TWO FORKED COPIES
# ============================================================
#
# resolve_real_path() below is hand-rolled (stock macOS has no `realpath`
# and no `readlink -f`) and took real engineering effort to get right across
# symlinked parents, symlinked leaves, `..`, trailing slashes, relative
# input, and targets that do not exist yet (12 scenarios in
# tests/install-self-sync-guard-test.sh). Two independent copies of this
# logic WILL drift the next time one of them gets a bugfix the other
# doesn't. Both install.sh and session-start-auto-install.sh source this
# ONE file for the detection primitives (`resolve_real_path`,
# `_sync_self_check`, `_resolves_into_dir`).
#
# What is deliberately NOT shared: each carrier's PRESENTATION of a detected
# self-sync. install.sh is operator-present (a human is watching stdout in
# real time), so its `sync_is_self_sync()` prints a full explanatory block
# per call and that stays local to install.sh. session-start-auto-install.sh
# runs unattended on every SessionStart and would emit that same block on
# EVERY file, EVERY session, forever on a symlinked-install machine -- so it
# aggregates into a counter folded into its one-line-per-run summary
# instead (see session-start-auto-install.sh header for the full
# skip-vs-louder reasoning). The primitives are identical; the reporting is
# intentionally carrier-specific.
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
