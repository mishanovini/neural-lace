#!/bin/bash
# pre-push-test-gate.sh
#
# Blocks `git push` when the local test suite has not been run + green
# against the current HEAD of the branch being pushed. Paired with
# server-side required-status-check branch protection, this gives two
# layers: local gate prevents pushing known-red code, remote gate
# prevents merging red PRs even if the local gate was bypassed.
#
# PAIRS WITH:
#   - `~/.claude/hooks/pre-push-scan.sh` (credential scanner, existing)
#   - Server-side: GitHub branch protection's required_status_checks
#
# HOW IT DECIDES THE BRANCH IS GREEN
#
# The hook looks for a "test receipt" file at:
#   <repo-root>/.claude/state/test-receipt-<branch-slug>-<head-sha>.txt
#
# A receipt file must exist AND contain the literal token:
#   TESTS_PASSED_FOR_SHA=<full-head-sha>
#
# Receipts are written by a helper the builder can invoke AFTER running
# tests successfully:
#   ~/.claude/scripts/record-test-pass.sh
#
# The script:
#   1. Resolves the current repo root + branch + HEAD SHA
#   2. Writes the receipt file with the SHA
#   3. Anything stale (receipts for prior SHAs) stays on disk but is
#      ignored by the gate — only the receipt for the *current* SHA
#      counts
#
# The gate on push:
#   1. Determines HEAD SHA being pushed (from stdin's pre-push format)
#   2. Looks for <repo>/.claude/state/test-receipt-<branch>-<sha>.txt
#   3. If absent → BLOCK with guidance
#   4. If present → allow push
#
# WHY A FILE RECEIPT AND NOT RUN-TESTS-IN-HOOK
#
# Running tests inside the pre-push hook would block every push for
# minutes (a full test suite for a typical project takes 2-5 minutes).
# That's hostile to a full-auto flow. The receipt pattern lets the builder run tests
# once, record the pass, then do whatever pushes it needs against
# that same SHA without re-running. Any new commit invalidates the
# receipt (because SHA changes), forcing a fresh test pass before
# the next push.
#
# ESCAPE HATCHES
#
# 1. `git push --no-verify` — standard git bypass. Use for docs-only
#    pushes or when pushing a work-in-progress branch that isn't
#    going to be merged directly (e.g., pushing to a feature branch
#    to get CI to run against a PR that'll be reviewed separately).
#
# 2. Environment variable `PT_PUSH_NO_TEST_GATE=1` — same effect as
#    --no-verify but scoped to this gate only (other hooks still run).
#    Use for automation that knows what it's doing (e.g., kanban
#    engine pushing build artifacts).
#
# 3. Branches not under production enforcement: anything other than
#    `master`/`main` is exempt by default. The gate only fires for
#    pushes to master/main since those are what GitHub's branch
#    protection covers. Feature branches push freely; their CI runs
#    on GitHub and the branch-protection-required check gates the
#    merge, not the branch push.
#
# REPO OPT-IN
#
# The gate is a no-op unless the repo has a marker file at:
#   <repo-root>/.claude/pre-push-test-gate.enabled
#
# This prevents the gate from surprising repos that haven't opted in.
# Repos that want the gate add an empty `.enabled` file; a single
# line in the repo's CLAUDE.md explains the pattern for new sessions.

set -u

# --- read git's pre-push stdin: <local_ref> <local_sha> <remote_ref> <remote_sha> ---
# We only care if we're pushing to master or main.

stdin_buf=$(cat)
if [ -z "$stdin_buf" ]; then
  # No refs on stdin (git was probably invoked without refs). Exit
  # cleanly — the credential scanner has its own stdin handling.
  exit 0
fi

# Detect target branch. pre-push format: per line "<local_ref> <local_sha> <remote_ref> <remote_sha>"
# remote_ref looks like "refs/heads/master" or "refs/heads/feat/xyz".

target_is_protected=0
head_sha=""
while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
  case "$remote_ref" in
    refs/heads/master|refs/heads/main)
      target_is_protected=1
      head_sha="$local_sha"
      break
      ;;
  esac
done <<< "$stdin_buf"

if [ "$target_is_protected" = "0" ]; then
  exit 0
fi

# --- escape hatch: env var bypass ---
if [ "${PT_PUSH_NO_TEST_GATE:-0}" = "1" ]; then
  echo "[pre-push-test-gate] PT_PUSH_NO_TEST_GATE=1 — allowing push" >&2
  exit 0
fi

# --- detect repo root ---
repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$repo_root" ]; then
  # not a git repo — shouldn't happen from pre-push, but bail safely
  exit 0
fi

# --- opt-in check ---
if [ ! -f "$repo_root/.claude/pre-push-test-gate.enabled" ]; then
  # repo hasn't opted in; exit silently
  exit 0
fi

# --- current branch name (for receipt lookup) ---
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
branch_slug=$(printf '%s' "$branch" | tr '/' '-' | tr -cd '[:alnum:]-')

if [ -z "$head_sha" ] || [ "$head_sha" = "0000000000000000000000000000000000000000" ]; then
  # Deletion or unusual push — allow
  exit 0
fi

receipt="$repo_root/.claude/state/test-receipt-${branch_slug}-${head_sha}.txt"

if [ ! -f "$receipt" ]; then
  cat >&2 <<EOF
==============================================================
[pre-push-test-gate] BLOCKED — no green-test receipt for current HEAD.

Branch: $branch
HEAD:   $head_sha
Repo:   $repo_root

You're pushing to a protected branch (master/main) without proof
that the test suite has passed locally for this exact SHA.

To unblock, ONE of:

  1. Run tests and record the pass:
       npm test  &&  ~/.claude/scripts/record-test-pass.sh

     (Substitute your repo's test command. Any passing run of the
     test suite is fine, but the receipt must match the current
     HEAD SHA — amending a commit or adding new commits invalidates it.)

  2. If this is a non-test push (docs-only, config, harness):
       PT_PUSH_NO_TEST_GATE=1 git push

     The receipt file at:
       $receipt
     can also be written by hand; the gate just checks for the file.

  3. Emergency bypass:  git push --no-verify

Design: this gate pairs with the GitHub branch-protection required-
status-check that blocks PRs with failing CI. Local gate catches
regressions before they leave the dev box; remote gate catches
them before they reach master. Both belt-and-suspenders.

See harness-architecture.md for the pattern rationale.
==============================================================
EOF
  exit 1
fi

# receipt present, verify it matches
if ! grep -q "TESTS_PASSED_FOR_SHA=$head_sha" "$receipt" 2>/dev/null; then
  cat >&2 <<EOF
[pre-push-test-gate] BLOCKED — receipt at $receipt does not contain
"TESTS_PASSED_FOR_SHA=$head_sha". Re-run tests and re-record.
EOF
  exit 1
fi

echo "[pre-push-test-gate] receipt OK for $head_sha; allowing push" >&2
exit 0
