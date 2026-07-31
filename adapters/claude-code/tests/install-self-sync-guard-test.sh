#!/usr/bin/env bash
# install-self-sync-guard-test.sh — regression test for install.sh's
# self-sync guard (SELF-SYNC-01, 2026-07-29).
#
# THE BUG THIS PINS (real data loss, twice in ten minutes on 2026-07-29):
#   On a SYMLINK-based install, ~/.claude/hooks is a symlink back into the
#   repo's adapters/claude-code/hooks. install.sh then runs
#     sync_directory "$ADAPTER_DIR/hooks/lib" "$CLAUDE_DIR/hooks/lib"
#   whose TARGET resolves, through that symlink, onto the SOURCE ITSELF.
#   The `[ -L "$dst" ]` branch never sees it (the PARENT is the symlink, the
#   leaf is a real directory), so control reaches `rm -rf "$dst"` and the
#   source tree is deleted -- 19 files / ~12,400 lines of hooks/lib,
#   admission-lib.sh among them. The subsequent copy loop then finds an empty
#   source and reports "synced hooks/lib/ (0 files)".
#
# The guard resolves both sides to a physical path and SKIPS the sync when
# they name the same object. On a copy-based install (the Windows machines)
# the two are genuinely different, so the guard never fires -- scenarios
# S5-S8 below are the "behaviour is unchanged when paths differ" half of the
# contract and are as load-bearing as the skip scenarios.
#
# Method: the REAL function bodies are extracted from install.sh at run time
# (no forked copy that can drift) and invoked directly against sandbox
# fixtures. Point INSTALL_SH_UNDER_TEST at a mutated copy to drive the
# mutation check (delete the guard -> S1-S4 must go RED).
#
# Usage:
#   bash tests/install-self-sync-guard-test.sh
#   INSTALL_SH_UNDER_TEST=/tmp/mutant.sh bash tests/install-self-sync-guard-test.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADAPTER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="${INSTALL_SH_UNDER_TEST:-$ADAPTER_DIR/install.sh}"

if [ ! -f "$INSTALL_SH" ]; then
  echo "FAIL: install.sh not found at $INSTALL_SH" >&2
  exit 1
fi

PASS=0
FAIL=0

SANDBOX_ROOT=$(mktemp -d -t nl-self-sync-test.XXXXXX 2>/dev/null) || SANDBOX_ROOT="/tmp/nl-self-sync-test.$$"
cleanup() { [ -n "${SANDBOX_ROOT:-}" ] && rm -rf "$SANDBOX_ROOT"; }
trap cleanup EXIT

# ------------------------------------------------------------
# Extract every TOP-LEVEL function definition from install.sh and source it.
# Top-level defs start at column 0 (`name() {`) and close with `}` at column
# 0; helpers nested inside a MODE branch are indented and are excluded.
# ------------------------------------------------------------
FUNCS="$SANDBOX_ROOT/install-funcs.sh"
awk '
  /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ { inf = 1 }
  inf                              { print }
  /^\}$/                           { if (inf) inf = 0 }
' "$INSTALL_SH" > "$FUNCS"

if ! grep -q '^sync_directory() {' "$FUNCS" || ! grep -q '^sync_file() {' "$FUNCS"; then
  echo "FAIL: could not extract sync_directory/sync_file from $INSTALL_SH" >&2
  exit 1
fi

# backup_if_real_file writes here; keep it inside the sandbox.
BACKUP_DIR="$SANDBOX_ROOT/backup"
BACKED_UP=0
# shellcheck disable=SC1090
. "$FUNCS"

ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1" >&2; FAIL=$((FAIL + 1)); }

# Populate $1 with $2 numbered .sh files whose content is derived from the name.
seed_tree() {
  local dir="$1" n="$2" i=1
  mkdir -p "$dir"
  while [ "$i" -le "$n" ]; do
    printf '#!/usr/bin/env bash\n# seeded file %s in %s\necho "%s"\n' "$i" "$(basename "$dir")" "$i" > "$dir/file-$i.sh"
    i=$((i + 1))
  done
}

# -L so a target that is a SYMLINK to a directory is counted through the link
# (plain `find` refuses to descend into a symlinked start point).
count_files() { find -L "$1" -type f 2>/dev/null | wc -l | tr -d '[:space:]'; }

# Every scenario gets its own disposable case dir AND its own BACKUP_DIR --
# backup_if_real_file copies to "$BACKUP_DIR/$(basename "$target")", so a
# shared backup dir makes two scenarios with the same leaf name (hooks/)
# collide and hash-mismatch.
# Sets the globals CASE_DIR and BACKUP_DIR (it must NOT be called in a
# command substitution -- that would confine the BACKUP_DIR assignment to a
# subshell and put every scenario back on one shared backup dir).
case_dir() {
  CASE_DIR="$SANDBOX_ROOT/$1"
  rm -rf "$CASE_DIR"
  mkdir -p "$CASE_DIR"
  BACKUP_DIR="$CASE_DIR/.backup"
}

# The skip message must name WHAT, WHY, and that it is expected/not an error.
assert_skip_message() {
  local name="$1" out="$2" label="$3"
  local missing=""
  echo "$out" | grep -q "SKIPPED" || missing="$missing SKIPPED-marker"
  echo "$out" | grep -qF -- "$label" || missing="$missing what($label)"
  echo "$out" | grep -qi "symlink" || missing="$missing why(symlink)"
  echo "$out" | grep -qi "not an error" || missing="$missing not-an-error"
  if [ -n "$missing" ]; then
    bad "$name: skip message incomplete (missing:$missing)"
    printf '        output was: %s\n' "$out" >&2
    return 1
  fi
  return 0
}

# ============================================================
# S1 -- THE PRODUCTION BUG: target's parent is a symlink to the source's
# parent, so src and dst are the same directory. Source must SURVIVE.
# ============================================================
s1() {
  local d; case_dir s1; d="$CASE_DIR"
  local src="$d/repo/adapters/claude-code/hooks/lib"
  seed_tree "$src" 19
  mkdir -p "$d/home/.claude"
  ln -s "$d/repo/adapters/claude-code/hooks" "$d/home/.claude/hooks"

  local before after out
  before=$(count_files "$src")
  out=$(sync_directory "$src" "$d/home/.claude/hooks/lib" "hooks/lib" 2>&1)
  after=$(count_files "$src")

  if [ "$before" != "19" ]; then bad "S1: fixture seeded $before files, expected 19"; return; fi
  if [ "$after" != "19" ]; then
    bad "S1 (symlinked parent): SOURCE DESTROYED -- $before files before, $after after"
    printf '        output was: %s\n' "$out" >&2
    return
  fi
  grep -q 'seeded file 7' "$src/file-7.sh" 2>/dev/null || { bad "S1: source content corrupted"; return; }
  assert_skip_message "S1" "$out" "hooks/lib" || return
  ok "S1 (symlinked parent, src==dst): all 19 source files survive + skip message"
}

# ============================================================
# S2 -- target IS a symlink to the source directory.
# ============================================================
s2() {
  local d; case_dir s2; d="$CASE_DIR"
  local src="$d/repo/hooks"
  seed_tree "$src" 5
  mkdir -p "$d/home/.claude"
  ln -s "$src" "$d/home/.claude/hooks"

  local out after
  out=$(sync_directory "$src" "$d/home/.claude/hooks" "hooks" 2>&1)
  after=$(count_files "$src")
  if [ "$after" != "5" ]; then bad "S2 (target->source symlink): source lost files ($after/5)"; return; fi
  assert_skip_message "S2" "$out" "hooks" || return
  ok "S2 (target is a symlink to source): source intact + skipped"
}

# ============================================================
# S3 -- source IS a symlink to the (real) target directory.
# ============================================================
s3() {
  local d; case_dir s3; d="$CASE_DIR"
  local real="$d/home/.claude/hooks"
  seed_tree "$real" 5
  mkdir -p "$d/repo"
  ln -s "$real" "$d/repo/hooks"

  local out after
  out=$(sync_directory "$d/repo/hooks" "$real" "hooks" 2>&1)
  after=$(count_files "$real")
  if [ "$after" != "5" ]; then bad "S3 (source->target symlink): target lost files ($after/5)"; return; fi
  assert_skip_message "S3" "$out" "hooks" || return
  ok "S3 (source is a symlink to target): files intact + skipped"
}

# ============================================================
# S4 -- both sides are symlinks to a third directory.
# ============================================================
s4() {
  local d; case_dir s4; d="$CASE_DIR"
  local third="$d/third/hooks"
  seed_tree "$third" 5
  mkdir -p "$d/repo" "$d/home/.claude"
  ln -s "$third" "$d/repo/hooks"
  ln -s "$third" "$d/home/.claude/hooks"

  local out after
  out=$(sync_directory "$d/repo/hooks" "$d/home/.claude/hooks" "hooks" 2>&1)
  after=$(count_files "$third")
  if [ "$after" != "5" ]; then bad "S4 (both -> third place): files lost ($after/5)"; return; fi
  assert_skip_message "S4" "$out" "hooks" || return
  ok "S4 (both sides symlink to a third dir): files intact + skipped"
}

# ============================================================
# S5 -- target's PARENT is a symlink but the leaf is a DIFFERENT real path.
# The guard must NOT fire; the sync must happen normally.
# ============================================================
s5() {
  local d; case_dir s5; d="$CASE_DIR"
  local src="$d/repo/hooks"
  seed_tree "$src" 4
  mkdir -p "$d/home/real-claude"
  ln -s "$d/home/real-claude" "$d/home/.claude"

  local out
  out=$(sync_directory "$src" "$d/home/.claude/hooks" "hooks" 2>&1)
  if echo "$out" | grep -q "SKIPPED"; then
    bad "S5 (symlinked PARENT, different leaf): guard over-fired -- sync was skipped"
    printf '        output was: %s\n' "$out" >&2
    return
  fi
  if [ "$(count_files "$d/home/real-claude/hooks")" != "4" ]; then
    bad "S5: expected 4 files at the target, found $(count_files "$d/home/real-claude/hooks")"
    return
  fi
  ok "S5 (parent symlinked, leaf differs): guard silent, 4 files delivered"
}

# ============================================================
# S6 -- COPY PATH, different paths: target pre-exists as a real directory so
# `ln -s` fails and control reaches the rm -rf + file-by-file copy -- the
# exact code path that destroyed the source in S1, here proven to still copy
# correctly (byte-for-byte) when the paths genuinely differ.
# ============================================================
s6() {
  local d; case_dir s6; d="$CASE_DIR"
  local src="$d/repo/hooks"
  seed_tree "$src" 6
  seed_tree "$src/nested" 3
  local dst="$d/home/.claude/hooks"
  mkdir -p "$dst"
  printf 'stale\n' > "$dst/stale-leftover.sh"

  local out
  out=$(sync_directory "$src" "$dst" "hooks" 2>&1)
  if echo "$out" | grep -q "SKIPPED"; then
    bad "S6 (copy path, different paths): guard over-fired"
    printf '        output was: %s\n' "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "synced hooks/ (9 files)"; then
    bad "S6: expected 'synced hooks/ (9 files)', got: $out"
    return
  fi
  if [ -e "$dst/stale-leftover.sh" ]; then
    bad "S6: stale target file survived -- rm -rf semantics changed"
    return
  fi
  if ! diff -r "$src" "$dst" >/dev/null 2>&1; then
    bad "S6: copied tree differs from source"
    diff -r "$src" "$dst" >&2
    return
  fi
  ok "S6 (copy path, different paths): 9 files copied, tree identical, stale file removed"
}

# ============================================================
# S7 -- target does not exist yet, different path: the symlink fast path.
# Also proves resolve-a-nonexistent-target does not crash the guard.
# ============================================================
s7() {
  local d; case_dir s7; d="$CASE_DIR"
  local src="$d/repo/hooks"
  seed_tree "$src" 3
  mkdir -p "$d/home/.claude"

  local out
  out=$(sync_directory "$src" "$d/home/.claude/hooks" "hooks" 2>&1)
  if echo "$out" | grep -q "SKIPPED"; then
    bad "S7 (nonexistent target): guard over-fired"
    printf '        output was: %s\n' "$out" >&2
    return
  fi
  if [ "$(count_files "$d/home/.claude/hooks")" != "3" ]; then
    bad "S7: expected 3 files reachable at the target"
    return
  fi
  ok "S7 (target does not exist yet, paths differ): sync proceeds, 3 files reachable"
}

# ============================================================
# S8 -- sync_file must carry the same guard: a single file reached through a
# symlinked parent would otherwise be `rm -f`'d and replaced by a symlink to
# the file just deleted (a dangling link + permanent content loss).
# ============================================================
s8() {
  local d; case_dir s8; d="$CASE_DIR"
  local hooks="$d/repo/adapters/claude-code/hooks"
  seed_tree "$hooks" 2
  mkdir -p "$d/home/.claude"
  ln -s "$hooks" "$d/home/.claude/hooks"

  local out
  out=$(sync_file "$hooks/file-1.sh" "$d/home/.claude/hooks/file-1.sh" "hooks/file-1.sh" 2>&1)
  if [ ! -f "$hooks/file-1.sh" ]; then
    bad "S8 (sync_file, symlinked parent): SOURCE FILE DESTROYED"
    printf '        output was: %s\n' "$out" >&2
    return
  fi
  if ! grep -q 'seeded file 1' "$hooks/file-1.sh"; then
    bad "S8: source file content lost"
    return
  fi
  assert_skip_message "S8" "$out" "hooks/file-1.sh" || return
  ok "S8 (sync_file, src==dst): source file survives + skipped"
}

# ============================================================
# S9 -- sync_file, different paths: unchanged behaviour.
# ============================================================
s9() {
  local d; case_dir s9; d="$CASE_DIR"
  mkdir -p "$d/repo" "$d/home/.claude"
  printf 'manifest\n' > "$d/repo/manifest.json"

  local out
  out=$(sync_file "$d/repo/manifest.json" "$d/home/.claude/manifest.json" "manifest.json" 2>&1)
  if echo "$out" | grep -q "SKIPPED"; then
    bad "S9 (sync_file, different paths): guard over-fired"
    return
  fi
  if [ "$(cat "$d/home/.claude/manifest.json" 2>/dev/null)" != "manifest" ]; then
    bad "S9: target content wrong"
    return
  fi
  ok "S9 (sync_file, different paths): file delivered as before"
}

# ============================================================
# S10 -- resolve_real_path unit checks: trailing slashes, `..`, symlinks and
# a target that does not exist yet must all normalise to the same answer.
# ============================================================
s10() {
  if ! command -v resolve_real_path >/dev/null 2>&1; then
    bad "S10: resolve_real_path is not defined in $INSTALL_SH"
    return
  fi
  local d; case_dir s10; d="$CASE_DIR"
  mkdir -p "$d/real/sub"
  ln -s "$d/real" "$d/link"
  local want
  want="$(cd "$d/real/sub" && pwd -P)"

  local got_plain got_slash got_dotdot got_link got_missing
  got_plain=$(resolve_real_path "$d/real/sub")
  got_slash=$(resolve_real_path "$d/real/sub///")
  got_dotdot=$(resolve_real_path "$d/real/sub/../sub")
  got_link=$(resolve_real_path "$d/link/sub")
  got_missing=$(resolve_real_path "$d/link/sub/not/here/yet")

  [ "$got_plain"  = "$want" ]              || { bad "S10: plain path -> $got_plain (want $want)"; return; }
  [ "$got_slash"  = "$want" ]              || { bad "S10: trailing slashes -> $got_slash (want $want)"; return; }
  [ "$got_dotdot" = "$want" ]              || { bad "S10: '..' -> $got_dotdot (want $want)"; return; }
  [ "$got_link"   = "$want" ]              || { bad "S10: via symlink -> $got_link (want $want)"; return; }
  [ "$got_missing" = "$want/not/here/yet" ] || { bad "S10: nonexistent tail -> $got_missing (want $want/not/here/yet)"; return; }
  ok "S10 (resolve_real_path): slashes, '..', symlinks and missing tails all normalise"
}

# ============================================================
# S11 -- sync_file where the TARGET is a symlink pointing straight at the
# source FILE. `cd`/`pwd -P` cannot resolve a file, so this exercises the
# hand-rolled readlink chain in resolve_real_path.
# ============================================================
s11() {
  local d; case_dir s11; d="$CASE_DIR"
  mkdir -p "$d/repo" "$d/home/.claude"
  printf 'payload\n' > "$d/repo/manifest.json"
  ln -s "$d/repo/manifest.json" "$d/home/.claude/manifest.json"

  local out
  out=$(sync_file "$d/repo/manifest.json" "$d/home/.claude/manifest.json" "manifest.json" 2>&1)
  if [ ! -f "$d/repo/manifest.json" ]; then
    bad "S11 (target symlink -> source file): SOURCE FILE DESTROYED"
    printf '        output was: %s\n' "$out" >&2
    return
  fi
  if [ "$(cat "$d/repo/manifest.json")" != "payload" ]; then bad "S11: source content lost"; return; fi
  assert_skip_message "S11" "$out" "manifest.json" || return
  ok "S11 (target symlink -> source file): source file intact + skipped"
}

# ============================================================
# S12 -- a DANGLING target symlink must not crash the guard or the sync: it
# resolves to a path that does not exist, which differs from the source, so
# the sync proceeds normally.
# ============================================================
s12() {
  local d; case_dir s12; d="$CASE_DIR"
  mkdir -p "$d/repo" "$d/home/.claude"
  printf 'payload\n' > "$d/repo/manifest.json"
  ln -s "$d/nowhere/gone.json" "$d/home/.claude/manifest.json"

  local out
  out=$(sync_file "$d/repo/manifest.json" "$d/home/.claude/manifest.json" "manifest.json" 2>&1)
  if echo "$out" | grep -q "SKIPPED"; then
    bad "S12 (dangling target symlink): guard over-fired"
    printf '        output was: %s\n' "$out" >&2
    return
  fi
  if [ "$(cat "$d/home/.claude/manifest.json" 2>/dev/null)" != "payload" ]; then
    bad "S12: target not delivered (got: $(cat "$d/home/.claude/manifest.json" 2>/dev/null))"
    return
  fi
  ok "S12 (dangling target symlink): no crash, guard silent, file delivered"
}

echo "install.sh self-sync guard test"
echo "  under test: $INSTALL_SH"
echo "  bash:       $BASH_VERSION"
echo ""

s1; s2; s3; s4; s5; s6; s7; s8; s9; s10; s11; s12

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
