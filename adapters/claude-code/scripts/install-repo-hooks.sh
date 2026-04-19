#!/bin/bash
# install-repo-hooks.sh — Install repo-local git hooks for the harness repo
#
# PURPOSE:
#   Wires the hygiene scanner (adapters/claude-code/hooks/harness-hygiene-scan.sh)
#   AND the document-freshness gates (decisions-index, backlog-plan atomicity,
#   docs-freshness, migration-CLAUDE.md atomicity, review-finding fix atomicity)
#   as this repo's `.git/hooks/pre-commit`. Each gate reads `git diff --cached`
#   and blocks commits that violate its rule.
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
#     wrapper (detected by sentinel comment supporting v1 OR v2), backs it up as
#     .git/hooks/pre-commit.backup-<timestamp>.
#   - Writes a thin wrapper that delegates to the 6-gate chain AND then
#     invokes .git/hooks/pre-commit.local if present (composable with other
#     dev tooling).
#   - Chmod +x.
#   - Idempotent: running twice does nothing destructive (the existing wrapper
#     is detected via sentinel and replaced without producing a backup of itself).
#   - Upgrade path: a v1 wrapper is detected and replaced in-place by v2 — no
#     backup file is produced for v1-managed wrappers (both are "ours").
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
#
# V1 wrapped just the hygiene scanner. V2 adds the document-freshness gates
# (decisions-index, backlog-plan atomicity, docs-freshness, migration-CLAUDE.md,
# review-finding fix). The idempotency check recognizes BOTH v1 and v2 so that
# re-running the installer on a repo with v1 upgrades to v2 without producing
# a backup of the v1 file.
# ---------------------------------------------------------------------------
SENTINEL_LINE="# NEURAL-LACE-HYGIENE-HOOK v2 — managed by install-repo-hooks.sh, safe to regenerate"
SENTINEL_REGEX="NEURAL-LACE-HYGIENE-HOOK v(1|2)"

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
  if grep -qE "$SENTINEL_REGEX" "$HOOK_PATH" 2>/dev/null; then
    : # Existing hook is already our wrapper (v1 or v2) — skip backup, just replace.
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
# Thin wrapper: runs the 6-gate document-freshness chain against the staged
# diff, then invokes any user-local hook at .git/hooks/pre-commit.local if
# present. Each gate reads \`git diff --cached\` and exits non-zero on
# violation; set -e propagates the failure.
#
# Chain order (first-failure-wins; hygiene scanner first — most common block):
#   1. harness-hygiene-scan.sh     — denylisted identity/credential patterns
#   2. decisions-index-gate.sh     — decision record ↔ DECISIONS.md atomicity
#   3. backlog-plan-atomicity.sh   — new plan absorbing backlog items
#   4. docs-freshness-gate.sh      — structural changes require docs staged
#   5. migration-claude-md-gate.sh — migrations ↔ CLAUDE.md atomicity (opt-in)
#   6. review-finding-fix-gate.sh  — review fixes update review file
#
# To regenerate: run adapters/claude-code/scripts/install-repo-hooks.sh
# To uninstall:  rm \$0
# To bypass:     git commit --no-verify  (not recommended)

set -e

REPO_ROOT="\$(git rev-parse --show-toplevel)"
HOOKS_DIR="\$REPO_ROOT/adapters/claude-code/hooks"

# Ordered list of gates to run. Missing gates skip silently (forward-compat
# with repos that may not have all hooks yet); broken gates fail loudly.
GATES=(
  "harness-hygiene-scan.sh"
  "decisions-index-gate.sh"
  "backlog-plan-atomicity.sh"
  "docs-freshness-gate.sh"
  "migration-claude-md-gate.sh"
  "review-finding-fix-gate.sh"
)

for gate in "\${GATES[@]}"; do
  gate_path="\$HOOKS_DIR/\$gate"
  if [ ! -f "\$gate_path" ]; then
    # Gate missing from tree — skip (not a hard error; wrapper predates gate).
    continue
  fi
  if [ -x "\$gate_path" ]; then
    "\$gate_path" || exit 1
  else
    # Fallback: exec bit lost, still runnable via bash
    bash "\$gate_path" || exit 1
  fi
done

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
echo "Installed: $HOOK_PATH (chain: hygiene + decisions-index + backlog-plan + docs-freshness + migration + review-finding)"
if [ -n "$BACKUP_PATH" ]; then
  echo "(backup: $BACKUP_PATH)"
fi
echo ""
echo "To test: make a staged change that violates any gate, run \`git commit --dry-run\`."
echo "To uninstall: rm $HOOK_PATH"
echo "To bypass (not recommended): git commit --no-verify"
