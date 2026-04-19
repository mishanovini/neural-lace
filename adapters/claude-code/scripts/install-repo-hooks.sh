#!/bin/bash
# install-repo-hooks.sh — Install repo-local git hooks for the harness repo
#
# PURPOSE:
#   Wires the hygiene scanner (adapters/claude-code/hooks/harness-hygiene-scan.sh)
#   as this repo's `.git/hooks/pre-commit`. The scanner reads the repo's denylist
#   and blocks commits containing sensitive identifiers.
#
#   This is REPO-LOCAL — it only affects commits in the harness repo itself.
#   It does NOT touch `git config --global core.hooksPath` (which points at the
#   different global pre-push scanner). A separate mechanism owns global hooks.
#
# INVOCATION:
#   Run manually once during dev setup, or invoked by install.sh:
#     ./adapters/claude-code/scripts/install-repo-hooks.sh
#
#   Must be run from somewhere inside the harness repo's working tree.
#
# BEHAVIOR:
#   - Resolves the repo root via `git rev-parse --show-toplevel`.
#   - Verifies the tree contains adapters/claude-code/hooks/harness-hygiene-scan.sh.
#   - If .git/hooks/pre-commit already exists AND is NOT a previously-installed
#     wrapper (detected by sentinel comment), backs it up as
#     .git/hooks/pre-commit.backup-<timestamp>.
#   - Writes a thin wrapper that delegates to the hygiene scanner AND then
#     invokes .git/hooks/pre-commit.local if present (composable with other
#     dev tooling).
#   - Chmod +x.
#   - Idempotent: running twice does nothing destructive (the existing wrapper
#     is detected via sentinel and replaced without producing a backup of itself).
#
# UNINSTALL:
#   rm .git/hooks/pre-commit
#   (optionally restore .git/hooks/pre-commit.backup-<timestamp>)
#
# BYPASS (not recommended):
#   git commit --no-verify

set -e

# ---------------------------------------------------------------------------
# Well-known sentinel comment — used to detect "is the existing hook mine?"
# ---------------------------------------------------------------------------
SENTINEL_LINE="# NEURAL-LACE-HYGIENE-HOOK v1 — managed by install-repo-hooks.sh, safe to regenerate"

# ---------------------------------------------------------------------------
# Resolve repo root
# ---------------------------------------------------------------------------
if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "ERROR: Not inside a git working tree." >&2
  echo "This script must be run from inside the Neural Lace repo root." >&2
  exit 1
fi

SCANNER_REL="adapters/claude-code/hooks/harness-hygiene-scan.sh"
SCANNER_PATH="$REPO_ROOT/$SCANNER_REL"

if [ ! -f "$SCANNER_PATH" ]; then
  echo "ERROR: Cannot locate hygiene scanner at:" >&2
  echo "  $SCANNER_PATH" >&2
  echo "" >&2
  echo "This script must be run from inside the Neural Lace repo root" >&2
  echo "(one that contains $SCANNER_REL)." >&2
  exit 1
fi

HOOK_DIR="$REPO_ROOT/.git/hooks"
HOOK_PATH="$HOOK_DIR/pre-commit"

mkdir -p "$HOOK_DIR"

# ---------------------------------------------------------------------------
# Back up existing pre-commit hook only if it is NOT our own wrapper
# (idempotency: re-running does not accumulate backups of our own output).
# ---------------------------------------------------------------------------
BACKUP_PATH=""
if [ -e "$HOOK_PATH" ]; then
  if grep -qF "$SENTINEL_LINE" "$HOOK_PATH" 2>/dev/null; then
    : # Existing hook is already our wrapper — skip backup, just replace.
  else
    BACKUP_PATH="$HOOK_PATH.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$HOOK_PATH" "$BACKUP_PATH"
  fi
fi

# ---------------------------------------------------------------------------
# Write the wrapper
# ---------------------------------------------------------------------------
cat > "$HOOK_PATH" <<EOF
#!/bin/bash
$SENTINEL_LINE
#
# Thin wrapper: delegates to the hygiene scanner (which reads the repo's
# denylist and scans \`git diff --cached\`), then invokes any user-local hook
# at .git/hooks/pre-commit.local if present.
#
# To regenerate: run adapters/claude-code/scripts/install-repo-hooks.sh
# To uninstall:  rm \$0
# To bypass:     git commit --no-verify  (not recommended)

set -e

REPO_ROOT="\$(git rev-parse --show-toplevel)"
SCANNER="\$REPO_ROOT/$SCANNER_REL"

if [ ! -x "\$SCANNER" ]; then
  if [ -f "\$SCANNER" ]; then
    # Fall back to invoking via bash if the executable bit was lost
    bash "\$SCANNER" || exit 1
  else
    echo "pre-commit: scanner missing at \$SCANNER" >&2
    echo "pre-commit: run adapters/claude-code/scripts/install-repo-hooks.sh to reinstall." >&2
    exit 1
  fi
else
  "\$SCANNER" || exit 1
fi

# Compose with any user-local pre-commit (never auto-generated; user-provided)
LOCAL_HOOK="\$REPO_ROOT/.git/hooks/pre-commit.local"
if [ -f "\$LOCAL_HOOK" ]; then
  if [ -x "\$LOCAL_HOOK" ]; then
    "\$LOCAL_HOOK" || exit 1
  else
    bash "\$LOCAL_HOOK" || exit 1
  fi
fi

exit 0
EOF

chmod +x "$HOOK_PATH"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "Neural Lace — Repo-local hook installer"
echo "Repo: $REPO_ROOT"
echo "Scanner: $SCANNER_PATH"
echo "Installed: $HOOK_PATH"
if [ -n "$BACKUP_PATH" ]; then
  echo "(backup: $BACKUP_PATH)"
fi
echo ""
echo "To test: make a staged change with a denylisted string, run \`git commit --dry-run\`."
echo "To uninstall: rm $HOOK_PATH"
echo "To bypass (not recommended): git commit --no-verify"
