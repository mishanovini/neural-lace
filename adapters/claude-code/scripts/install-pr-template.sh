#!/usr/bin/env bash
# install-pr-template.sh — Roll out the capture-codify PR template to a target repo.
#
# Copies four artifacts into a target downstream repo:
#   1. .github/PULL_REQUEST_TEMPLATE.md    (the PR template body)
#   2. .github/workflows/pr-template-check.yml  (the CI workflow)
#   3. .github/scripts/validate-pr-template.sh  (the shared validator library)
#   4. .git/hooks/pre-push                  (the local pre-push hook,
#                                            renamed from pre-push-pr-template.sh)
#
# Idempotent: re-running over an existing install is safe. Files that already
# match the source byte-for-byte are skipped silently. Files that exist but
# differ produce a stderr warning and are NOT overwritten unless --force is
# passed (the user is expected to diff and reconcile).
#
# Bash 3.2+ compatible (macOS default). No associative arrays, no mapfile.
#
# USAGE
#   install-pr-template.sh <target-repo-path> [--force] [--no-hook]
#   install-pr-template.sh --self-test
#
# OPTIONS
#   --force     Overwrite divergent files without warning.
#   --no-hook   Install template + workflow + validator only; skip the local
#               pre-push hook (useful when the target repo already has a
#               pre-push hook the user does not want to clobber).
#   --self-test Run internal assertions in a temp repo; print OK/FAIL; exit.
#
# EXIT CODES
#   0 — install complete (or self-test passed)
#   1 — invalid arguments / target not a git repo
#   2 — source files missing in the harness repo
#   3 — divergent file detected without --force
#
# CROSS-REFERENCES
#   - Plan: docs/plans/capture-codify-pr-template.md (Task A.11)
#   - Decision 007: per-repo opt-in for the local hook (decisions/007-*.md)
#   - Decision 010: validator library at .github/scripts/ (decisions/010-*.md)

set -eo pipefail

# --- Self-test mode -----------------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  HARNESS_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

  # Verify source files exist in the harness repo before the test
  for src in \
      "$HARNESS_ROOT/.github/PULL_REQUEST_TEMPLATE.md" \
      "$HARNESS_ROOT/.github/workflows/pr-template-check.yml" \
      "$HARNESS_ROOT/.github/scripts/validate-pr-template.sh" \
      "$HARNESS_ROOT/adapters/claude-code/git-hooks/pre-push-pr-template.sh"; do
    if [ ! -f "$src" ]; then
      echo "self-test: FAIL — source file missing: $src" >&2
      exit 1
    fi
  done

  # Initialize a temp target repo
  TARGET="$TMPDIR_ST/target"
  mkdir -p "$TARGET"
  (cd "$TARGET" && git init -q . && git config user.email "selftest@example.test" && git config user.name "selftest")

  # First install
  if ! bash "$SCRIPT_PATH" "$TARGET" >/dev/null 2>&1; then
    echo "self-test: FAIL — first install errored" >&2
    exit 1
  fi

  # Verify all four artifacts exist
  for artifact in \
      ".github/PULL_REQUEST_TEMPLATE.md" \
      ".github/workflows/pr-template-check.yml" \
      ".github/scripts/validate-pr-template.sh" \
      ".git/hooks/pre-push"; do
    if [ ! -f "$TARGET/$artifact" ]; then
      echo "self-test: FAIL — artifact missing after install: $artifact" >&2
      exit 1
    fi
  done
  echo "self-test: case 'fresh install' OK"

  # Validator library and pre-push hook should be executable
  if [ ! -x "$TARGET/.github/scripts/validate-pr-template.sh" ]; then
    echo "self-test: FAIL — validator library not executable" >&2
    exit 1
  fi
  if [ ! -x "$TARGET/.git/hooks/pre-push" ]; then
    echo "self-test: FAIL — pre-push hook not executable" >&2
    exit 1
  fi
  echo "self-test: case 'executable bits set' OK"

  # Idempotency: second run should succeed silently with no errors
  if ! bash "$SCRIPT_PATH" "$TARGET" >/dev/null 2>&1; then
    echo "self-test: FAIL — second (idempotent) install errored" >&2
    exit 1
  fi
  echo "self-test: case 'idempotent re-run' OK"

  # Divergent-file detection: modify one artifact, then re-run without --force
  echo "# tampered" >> "$TARGET/.github/PULL_REQUEST_TEMPLATE.md"
  set +e
  bash "$SCRIPT_PATH" "$TARGET" >/dev/null 2>&1
  RC=$?
  set -e
  if [ "$RC" -ne 3 ]; then
    echo "self-test: FAIL — expected exit 3 on divergent file, got $RC" >&2
    exit 1
  fi
  echo "self-test: case 'divergent file blocks without --force' OK"

  # --force should overwrite the tampered file
  if ! bash "$SCRIPT_PATH" "$TARGET" --force >/dev/null 2>&1; then
    echo "self-test: FAIL — --force did not overwrite tampered file" >&2
    exit 1
  fi
  if grep -q '^# tampered' "$TARGET/.github/PULL_REQUEST_TEMPLATE.md"; then
    echo "self-test: FAIL — tampered marker still present after --force" >&2
    exit 1
  fi
  echo "self-test: case '--force overwrites tampered file' OK"

  # --no-hook should skip the pre-push hook only (others still installed)
  TARGET2="$TMPDIR_ST/target-nohook"
  mkdir -p "$TARGET2"
  (cd "$TARGET2" && git init -q . && git config user.email "selftest@example.test" && git config user.name "selftest")
  if ! bash "$SCRIPT_PATH" "$TARGET2" --no-hook >/dev/null 2>&1; then
    echo "self-test: FAIL — --no-hook install errored" >&2
    exit 1
  fi
  if [ -f "$TARGET2/.git/hooks/pre-push" ]; then
    echo "self-test: FAIL — --no-hook still installed pre-push hook" >&2
    exit 1
  fi
  if [ ! -f "$TARGET2/.github/PULL_REQUEST_TEMPLATE.md" ]; then
    echo "self-test: FAIL — --no-hook did not install template" >&2
    exit 1
  fi
  echo "self-test: case '--no-hook skips hook only' OK"

  echo "self-test: OK"
  exit 0
fi

# --- Argument parsing ---------------------------------------------------------

TARGET=""
FORCE=0
NO_HOOK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --no-hook) NO_HOOK=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    -*)
      echo "install-pr-template: unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"
      else
        echo "install-pr-template: unexpected positional argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "install-pr-template: missing target repo path" >&2
  echo "usage: install-pr-template.sh <target-repo-path> [--force] [--no-hook]" >&2
  exit 1
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "install-pr-template: $TARGET is not a git repo (no .git directory)" >&2
  exit 1
fi

TARGET_ABS="$(cd "$TARGET" && pwd)"

# --- Resolve harness source paths --------------------------------------------

# This script lives at <harness>/adapters/claude-code/scripts/install-pr-template.sh
HARNESS_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

SRC_TEMPLATE="$HARNESS_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
SRC_WORKFLOW="$HARNESS_ROOT/.github/workflows/pr-template-check.yml"
SRC_VALIDATOR="$HARNESS_ROOT/.github/scripts/validate-pr-template.sh"
SRC_HOOK="$HARNESS_ROOT/adapters/claude-code/git-hooks/pre-push-pr-template.sh"

for src in "$SRC_TEMPLATE" "$SRC_WORKFLOW" "$SRC_VALIDATOR" "$SRC_HOOK"; do
  if [ ! -f "$src" ]; then
    echo "install-pr-template: source file missing in harness: $src" >&2
    exit 2
  fi
done

# --- Helper: copy with idempotency + divergence detection --------------------

copy_artifact() {
  local src="$1"
  local dest="$2"
  local mode="${3:-644}"

  mkdir -p "$(dirname "$dest")"

  if [ -f "$dest" ]; then
    if cmp -s "$src" "$dest"; then
      printf '  skip (identical): %s\n' "${dest#$TARGET_ABS/}"
      return 0
    fi
    if [ "$FORCE" -eq 0 ]; then
      printf '  DIVERGENT: %s (existing file differs from harness source; pass --force to overwrite)\n' "${dest#$TARGET_ABS/}" >&2
      return 3
    fi
    printf '  overwrite (--force): %s\n' "${dest#$TARGET_ABS/}"
  else
    printf '  install: %s\n' "${dest#$TARGET_ABS/}"
  fi

  cp "$src" "$dest"
  chmod "$mode" "$dest"
  return 0
}

# --- Perform installation ----------------------------------------------------

printf 'install-pr-template: target=%s\n' "$TARGET_ABS"

DIVERGENT=0

copy_artifact "$SRC_TEMPLATE" "$TARGET_ABS/.github/PULL_REQUEST_TEMPLATE.md" 644 || DIVERGENT=1
copy_artifact "$SRC_WORKFLOW" "$TARGET_ABS/.github/workflows/pr-template-check.yml" 644 || DIVERGENT=1
copy_artifact "$SRC_VALIDATOR" "$TARGET_ABS/.github/scripts/validate-pr-template.sh" 755 || DIVERGENT=1

if [ "$NO_HOOK" -eq 0 ]; then
  copy_artifact "$SRC_HOOK" "$TARGET_ABS/.git/hooks/pre-push" 755 || DIVERGENT=1
else
  printf '  skip (--no-hook): .git/hooks/pre-push\n'
fi

if [ "$DIVERGENT" -ne 0 ]; then
  printf '\ninstall-pr-template: BLOCKED — one or more existing files diverge from the harness source.\n' >&2
  printf 'Diff each divergent file, decide whether to keep local changes or overwrite, then re-run with --force.\n' >&2
  exit 3
fi

printf '\ninstall-pr-template: complete. Next steps:\n'
printf '  1. Open a draft PR in %s and verify "PR Template Check / validate" appears.\n' "$TARGET_ABS"
printf '  2. (Optional) Configure branch protection to require this check on master.\n'
printf '  3. (Optional) Run `bash %s/adapters/claude-code/scripts/audit-merged-prs.sh --limit 5` to retroactively check past merges.\n' "$HARNESS_ROOT"
exit 0
