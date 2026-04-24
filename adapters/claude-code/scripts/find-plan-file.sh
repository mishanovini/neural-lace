#!/bin/bash
# find-plan-file.sh
#
# Archive-aware plan file resolver. Given a plan slug (with or without
# the `.md` extension), prints the relative path to the plan file from
# the current repo root.
#
# Resolution order:
#   1. docs/plans/<slug>.md          (active)
#   2. docs/plans/archive/<slug>.md  (archived; emits stderr note)
#
# Glob patterns are supported: `find-plan-file.sh "*release*"` lists
# every match across both directories (active first, then archive).
#
# Exit codes:
#   0 — at least one match found; paths printed to stdout (one per line)
#   1 — no match; nothing printed to stdout (errors go to stderr)
#   2 — usage error (missing argument, bad flag)
#
# Stderr conventions:
#   - On a single archive-only resolution: prints
#     "find-plan-file.sh: resolved from archive: <path>"
#   - On glob matches that include archive entries: same line per
#     archive match, so callers piping stdout to a tool see only paths
#     and a human watching stderr sees the archive provenance.
#
# Usage:
#   find-plan-file.sh <slug>            # plain slug, with or without .md
#   find-plan-file.sh "<glob-pattern>"  # quoted to defer expansion
#   find-plan-file.sh --self-test       # exercise resolution scenarios
#   find-plan-file.sh --help
#
# Bash 3.2 portability: avoid `mapfile`, `declare -A`, `${var,,}`,
# `&>>`. Tested on macOS bash 3.2 + Linux bash 5.x + Git Bash on
# Windows.
#
# This helper does NOT change directory. It assumes the caller's CWD
# is the repo root (typical for hooks and Claude Code sessions). If
# the active or archive directory does not exist, the helper treats
# it as empty (no error).

set -u

SCRIPT_NAME="find-plan-file.sh"
ACTIVE_DIR="docs/plans"
ARCHIVE_DIR="docs/plans/archive"

# ---------- helpers ----------------------------------------------------

# Normalize a slug to a basename ending in `.md`. Strips a leading
# `docs/plans/` or `docs/plans/archive/` prefix if the caller passed a
# full-ish path. Strips a trailing `/` (defensive). Adds `.md` if the
# caller omitted the extension.
normalize_slug() {
  local s
  s="$1"
  # Strip directory prefixes if present.
  s="${s#docs/plans/archive/}"
  s="${s#docs/plans/}"
  # Strip trailing slash (defensive).
  s="${s%/}"
  # Append .md if missing AND the slug doesn't already end with .md.
  # Glob patterns containing `*` are left alone — a glob like `*release*`
  # should match both `*release*.md` files; we add the .md filter via
  # the find pattern below, not by mutating the slug.
  case "$s" in
    *\**|*\?*|*\[*) printf '%s' "$s" ;;
    *.md) printf '%s' "$s" ;;
    *) printf '%s.md' "$s" ;;
  esac
}

# Detect whether a slug contains glob metacharacters.
is_glob() {
  case "$1" in
    *\**|*\?*|*\[*) return 0 ;;
    *) return 1 ;;
  esac
}

# Run the resolution. Sets two globals via stdout streams instead of
# arrays (Bash 3.2 lacks `mapfile`):
#   - prints active matches first, one per line
#   - then prints archive matches, one per line, each preceded on
#     stderr by the resolved-from-archive note
# Returns 0 if at least one match printed, 1 otherwise.
resolve() {
  local slug pattern found
  slug="$1"
  found=0

  if is_glob "$slug"; then
    # Glob mode: ensure pattern ends in .md so we don't match
    # arbitrary files. Append .md if not already present anywhere
    # in the trailing chunk of the slug.
    case "$slug" in
      *.md) pattern="$slug" ;;
      *) pattern="${slug}.md" ;;
    esac

    # Active matches.
    if [ -d "$ACTIVE_DIR" ]; then
      # Use find to avoid noglob/nullglob portability issues.
      local m
      while IFS= read -r m; do
        [ -n "$m" ] || continue
        printf '%s\n' "$m"
        found=1
      done < <(find "$ACTIVE_DIR" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | LC_ALL=C sort)
    fi

    # Archive matches.
    if [ -d "$ARCHIVE_DIR" ]; then
      local m
      while IFS= read -r m; do
        [ -n "$m" ] || continue
        printf '%s\n' "$m"
        printf '%s: resolved from archive: %s\n' "$SCRIPT_NAME" "$m" >&2
        found=1
      done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | LC_ALL=C sort)
    fi
  else
    # Plain slug mode: try active first, then archive. Single match.
    pattern="$slug"
    local active_path="$ACTIVE_DIR/$pattern"
    local archive_path="$ARCHIVE_DIR/$pattern"
    if [ -f "$active_path" ]; then
      printf '%s\n' "$active_path"
      found=1
    elif [ -f "$archive_path" ]; then
      printf '%s\n' "$archive_path"
      printf '%s: resolved from archive: %s\n' "$SCRIPT_NAME" "$archive_path" >&2
      found=1
    fi
  fi

  if [ "$found" = "1" ]; then
    return 0
  fi
  return 1
}

# ---------- self-test --------------------------------------------------

run_self_test() {
  local tmp script_path
  script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  # NOTE: SELF_TEST_ORIGINAL_PWD and SELF_TEST_TMP are intentionally
  # global (not `local`) so the EXIT trap can reference them after this
  # function returns. With `set -u`, `local` variables go out of scope
  # before the trap fires, which causes an "unbound variable" error.
  SELF_TEST_ORIGINAL_PWD="$PWD"
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t findplantest)"
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    printf 'self-test: failed to create temp dir\n' >&2
    return 1
  fi
  SELF_TEST_TMP="$tmp"
  trap 'cd "$SELF_TEST_ORIGINAL_PWD" 2>/dev/null; rm -rf "$SELF_TEST_TMP"' EXIT

  cd "$tmp" || return 1
  mkdir -p docs/plans/archive

  # Layout for the test:
  #   docs/plans/active-one.md
  #   docs/plans/active-release-train.md
  #   docs/plans/archive/old-one.md
  #   docs/plans/archive/old-release-thing.md
  #   docs/plans/dual-name.md           ← also exists in archive (active wins)
  #   docs/plans/archive/dual-name.md
  printf 'active one\n' > docs/plans/active-one.md
  printf 'active release train\n' > docs/plans/active-release-train.md
  printf 'old one\n' > docs/plans/archive/old-one.md
  printf 'old release thing\n' > docs/plans/archive/old-release-thing.md
  printf 'active dual\n' > docs/plans/dual-name.md
  printf 'archive dual\n' > docs/plans/archive/dual-name.md

  local pass=0 fail=0

  check() {
    local label="$1" expect_rc="$2" expect_stdout_contains="$3" expect_stderr_contains="$4"
    shift 4
    local got_out got_err got_rc
    got_out=$("$@" 2>/tmp/find-plan-self-test.err)
    got_rc=$?
    got_err=$(cat /tmp/find-plan-self-test.err)
    rm -f /tmp/find-plan-self-test.err

    if [ "$got_rc" != "$expect_rc" ]; then
      printf 'FAIL [%s]: expected rc=%s got rc=%s; out=%q err=%q\n' \
        "$label" "$expect_rc" "$got_rc" "$got_out" "$got_err" >&2
      fail=$((fail + 1))
      return
    fi
    if [ -n "$expect_stdout_contains" ]; then
      case "$got_out" in
        *"$expect_stdout_contains"*) ;;
        *)
          printf 'FAIL [%s]: stdout missing %q; got %q\n' \
            "$label" "$expect_stdout_contains" "$got_out" >&2
          fail=$((fail + 1))
          return
          ;;
      esac
    fi
    if [ -n "$expect_stderr_contains" ]; then
      case "$got_err" in
        *"$expect_stderr_contains"*) ;;
        *)
          printf 'FAIL [%s]: stderr missing %q; got %q\n' \
            "$label" "$expect_stderr_contains" "$got_err" >&2
          fail=$((fail + 1))
          return
          ;;
      esac
    fi
    pass=$((pass + 1))
  }

  # 1. Plain slug, active hit.
  check "active-plain-with-md" 0 "docs/plans/active-one.md" "" \
    bash "$script_path" active-one.md

  # 2. Plain slug, active hit, no extension.
  check "active-plain-no-ext" 0 "docs/plans/active-one.md" "" \
    bash "$script_path" active-one

  # 3. Plain slug, archive-only hit, with stderr note.
  check "archive-fallback" 0 "docs/plans/archive/old-one.md" "resolved from archive" \
    bash "$script_path" old-one

  # 4. Plain slug, dual-existence — active wins, no stderr note.
  local dual_out dual_err
  dual_out=$(bash "$script_path" dual-name 2>/tmp/find-plan-dual.err)
  dual_err=$(cat /tmp/find-plan-dual.err)
  rm -f /tmp/find-plan-dual.err
  if [ "$dual_out" = "docs/plans/dual-name.md" ] && [ -z "$dual_err" ]; then
    pass=$((pass + 1))
  else
    printf 'FAIL [dual-name-active-wins]: out=%q err=%q\n' "$dual_out" "$dual_err" >&2
    fail=$((fail + 1))
  fi

  # 5. Not found.
  check "not-found" 1 "" "" \
    bash "$script_path" no-such-plan

  # 6. Glob, active matches only.
  check "glob-active" 0 "docs/plans/active-release-train.md" "" \
    bash "$script_path" "*active-release*"

  # 7. Glob, both active and archive — both should appear in stdout,
  # archive note on stderr.
  local glob_out glob_err
  glob_out=$(bash "$script_path" "*release*" 2>/tmp/find-plan-glob.err)
  glob_err=$(cat /tmp/find-plan-glob.err)
  rm -f /tmp/find-plan-glob.err
  case "$glob_out" in
    *"docs/plans/active-release-train.md"*"docs/plans/archive/old-release-thing.md"*)
      case "$glob_err" in
        *"resolved from archive"*)
          pass=$((pass + 1))
          ;;
        *)
          printf 'FAIL [glob-archive-stderr]: stderr missing archive note; err=%q\n' "$glob_err" >&2
          fail=$((fail + 1))
          ;;
      esac
      ;;
    *)
      printf 'FAIL [glob-both]: out missing one match; out=%q\n' "$glob_out" >&2
      fail=$((fail + 1))
      ;;
  esac

  # 8. Glob no match.
  check "glob-no-match" 1 "" "" \
    bash "$script_path" "*nothing-matches*"

  # 9. Usage error: no args.
  check "usage-no-args" 2 "" "Usage" \
    bash "$script_path"

  # 10. Help flag.
  check "help-flag" 0 "Usage" "" \
    bash "$script_path" --help

  # 11. Path-prefixed slug is normalized correctly.
  check "path-prefixed-slug" 0 "docs/plans/active-one.md" "" \
    bash "$script_path" docs/plans/active-one.md

  # 12. Archive-prefixed slug routes through normalization too — falls
  # back to archive resolution.
  check "archive-prefixed-slug" 0 "docs/plans/archive/old-one.md" "resolved from archive" \
    bash "$script_path" docs/plans/archive/old-one.md

  # 13. Missing active dir does not error (delete and retry not-found).
  rm -rf docs/plans
  mkdir -p docs/plans/archive
  printf 'still here\n' > docs/plans/archive/orphan.md
  check "active-dir-missing-archive-hits" 0 "docs/plans/archive/orphan.md" "resolved from archive" \
    bash "$script_path" orphan

  rm -rf docs/plans
  check "both-dirs-missing-not-found" 1 "" "" \
    bash "$script_path" anything

  if [ "$fail" = "0" ]; then
    printf 'OK (%s --self-test) — %s scenarios passed\n' "$SCRIPT_NAME" "$pass"
    return 0
  else
    printf 'FAIL (%s --self-test) — %s passed, %s failed\n' "$SCRIPT_NAME" "$pass" "$fail" >&2
    return 1
  fi
}

# ---------- usage ------------------------------------------------------

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <slug-or-pattern>
       $SCRIPT_NAME --self-test
       $SCRIPT_NAME --help

Resolves a plan slug to a relative path, preferring active plans
(docs/plans/<slug>.md) and falling back to archived plans
(docs/plans/archive/<slug>.md). Glob patterns supported when the slug
contains *, ?, or [...].

Exit codes:
  0 — at least one match (paths on stdout)
  1 — no match
  2 — usage error
EOF
}

# ---------- main -------------------------------------------------------

main() {
  if [ "$#" -lt 1 ]; then
    usage >&2
    return 2
  fi

  case "$1" in
    --self-test)
      run_self_test
      return $?
      ;;
    --help|-h)
      usage
      return 0
      ;;
    --*)
      printf '%s: unknown flag: %s\n' "$SCRIPT_NAME" "$1" >&2
      usage >&2
      return 2
      ;;
  esac

  local slug
  slug=$(normalize_slug "$1")
  resolve "$slug"
}

main "$@"
