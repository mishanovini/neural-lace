#!/bin/bash
# observed-errors-gate.sh
#
# PreToolUse hook on Bash (git commit) that blocks fix-class commits
# unless the agent has captured a verbatim error in
# `.claude/state/observed-errors.md` from the current session.
#
# Why: in a representative incident, the agent saw an HTTP 500 returned
# from a test five times before reading the response body. The body
# contained the actual root cause (a schema/enum mismatch unrelated to
# the agent's work). Cost of NOT reading: ~150-200k wasted tokens
# iterating on the wrong hypothesis. Cost of reading: 30 seconds.
# This gate forces the read by demanding a captured error before fix
# commits are accepted.
#
# Rule: ~/.claude/rules/observed-errors-first.md
# Audit lens applied: ~/.claude/docs/harness-review-audit-questions.md
#   — triggers on observable commit shape (not self-classification),
#     narrow remedy (one file), low cheap-evasion paths.
#
# Exit codes:
#   0 — commit allowed
#   1 — commit blocked (stderr explains)

set -e

INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  if [[ ! -t 0 ]]; then
    INPUT=$(cat 2>/dev/null || echo "")
  fi
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || echo "")
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only fire on git commit (not log, not diff, not amend without changes)
if ! echo "$COMMAND" | grep -qE '(^|[[:space:]])git[[:space:]]+commit'; then
  exit 0
fi

# Skip merge commits — they're not fixes
if echo "$COMMAND" | grep -qE 'git[[:space:]]+commit.*--merge\b'; then
  exit 0
fi

# Find repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi

# Override: env var bypass with logged justification
if [[ -n "${OBSERVED_ERRORS_OVERRIDE:-}" ]]; then
  mkdir -p "$REPO_ROOT/.claude/state"
  printf '%s\t%s\t%s\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    "$OBSERVED_ERRORS_OVERRIDE" \
    "$(echo "$COMMAND" | head -c 200)" \
    >> "$REPO_ROOT/.claude/state/observed-errors-overrides.log"
  exit 0
fi

# Extract commit message from command
# Handles: -m "msg", -m 'msg', --message=msg, -F file (read file contents)
COMMIT_MSG=""
if echo "$COMMAND" | grep -qE '\-m[[:space:]]'; then
  # Extract -m argument, handling quotes; use Python-like sed for either quote style
  COMMIT_MSG=$(echo "$COMMAND" | sed -nE 's/.*-m[[:space:]]+"([^"]*)".*/\1/p' | head -1)
  if [[ -z "$COMMIT_MSG" ]]; then
    COMMIT_MSG=$(echo "$COMMAND" | sed -nE "s/.*-m[[:space:]]+'([^']*)'.*/\\1/p" | head -1)
  fi
fi
if [[ -z "$COMMIT_MSG" ]] && echo "$COMMAND" | grep -qE '\-F[[:space:]]'; then
  MSG_FILE=$(echo "$COMMAND" | sed -nE 's/.*-F[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
  if [[ -n "$MSG_FILE" && -f "$REPO_ROOT/$MSG_FILE" ]]; then
    COMMIT_MSG=$(cat "$REPO_ROOT/$MSG_FILE" 2>/dev/null || echo "")
  elif [[ -n "$MSG_FILE" && -f "$MSG_FILE" ]]; then
    COMMIT_MSG=$(cat "$MSG_FILE" 2>/dev/null || echo "")
  fi
fi

# Heredoc-style commit messages: extract content between EOF / 'EOF'
# Pattern: $(cat <<'EOF' ... EOF) or $(cat <<EOF ... EOF)
if [[ -z "$COMMIT_MSG" ]] && echo "$COMMAND" | grep -qE "<<['\"]?EOF['\"]?"; then
  # Best-effort: capture the content between EOF markers
  COMMIT_MSG=$(echo "$COMMAND" | awk '/<<.?EOF.?$/{flag=1; next} /^EOF$/{flag=0} flag' 2>/dev/null || echo "")
fi

# If still empty, can't determine — fail open (don't block)
if [[ -z "$COMMIT_MSG" ]]; then
  exit 0
fi

# Does the message indicate a fix?
if ! echo "$COMMIT_MSG" | grep -qiE '\b(fix|fixed|fixes|bug|broken|regression|repair|resolve|resolved|hotfix)\b'; then
  exit 0
fi

# Skip docs-only commits (only *.md files staged)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=AM 2>/dev/null || echo "")
if [[ -z "$STAGED_FILES" ]]; then
  exit 0
fi
NON_DOC_FILES=$(echo "$STAGED_FILES" | grep -vE '\.md$' || true)
if [[ -z "$NON_DOC_FILES" ]]; then
  exit 0
fi

# Skip pure chore/style/refactor commits
if echo "$COMMIT_MSG" | head -1 | grep -qE '^(chore|style|refactor)(\([^)]+\))?:'; then
  # Even if "fix" appears later, the commit-type prefix governs
  exit 0
fi

# At this point: this looks like a fix-class commit touching code.
# Check for the observed-errors artifact.
ERRORS_FILE="$REPO_ROOT/.claude/state/observed-errors.md"

if [[ ! -f "$ERRORS_FILE" ]]; then
  cat >&2 <<'ERR_MSG'
[observed-errors-gate] BLOCKED: this commit looks like a fix but no observed-errors trail exists.

Rule: ~/.claude/rules/observed-errors-first.md
Why: on 2026-04-25 the agent saw HTTP 500 five times before reading the
response body, which would have given the root cause instantly. This
gate forces you to read the body / capture the actual error before
shipping a fix.

To proceed, append a real observation to .claude/state/observed-errors.md:

  ## YYYY-MM-DD HH:MM — <one-line description>
  Reproduction: <command or steps>
  <verbatim error: status code + body, OR exception + stack frame, OR
   test failure with expected vs received, OR console output verbatim>
  Hypothesis: <what you think the cause is, derived from the observation>

If this fix genuinely has no runtime symptom (e.g., a code-review-only
catch), set OBSERVED_ERRORS_OVERRIDE="<reason>" in your env for this
commit. The override is logged at .claude/state/observed-errors-overrides.log
for periodic review.
ERR_MSG
  exit 1
fi

# File exists. Was it modified recently (last 60 minutes)?
# Use stat with portable form. macOS uses -f, GNU uses -c.
MTIME=$(stat -c %Y "$ERRORS_FILE" 2>/dev/null || stat -f %m "$ERRORS_FILE" 2>/dev/null || echo 0)
NOW=$(date +%s)
AGE=$(( NOW - MTIME ))

if (( AGE > 3600 )); then
  cat >&2 <<ERR_MSG
[observed-errors-gate] BLOCKED: .claude/state/observed-errors.md exists but
was last modified $((AGE / 60)) minutes ago — older than the 60-minute
freshness window. The current session needs its own captured error.

Append a fresh entry, or set OBSERVED_ERRORS_OVERRIDE="<reason>" if this
fix has no runtime symptom in the current session.

Rule: ~/.claude/rules/observed-errors-first.md
ERR_MSG
  exit 1
fi

# File exists and is fresh. Does it contain a recognizable error?
# Look for at least one of:
#   - HTTP status code (4xx/5xx)
#   - Exception keyword + something resembling a stack frame ("at " line)
#   - "Error:" or "Exception:" markers
#   - Test assertion (expected/received)
#   - Console error markers
RECOGNIZABLE=0
if grep -qE '\b(4[0-9]{2}|5[0-9]{2})\b' "$ERRORS_FILE"; then RECOGNIZABLE=1; fi
if grep -qE '\b(Error|Exception|TypeError|ReferenceError|AssertionError|TimeoutError):' "$ERRORS_FILE"; then RECOGNIZABLE=1; fi
if grep -qE '^\s*at\s+[A-Za-z_][A-Za-z0-9_.]*\s*\(' "$ERRORS_FILE"; then RECOGNIZABLE=1; fi
if grep -qiE '(expected|received|to be|toBe|toEqual)' "$ERRORS_FILE"; then RECOGNIZABLE=1; fi
if grep -qE '(console\.(error|warn)|FAIL\s|✗|×|✘)' "$ERRORS_FILE"; then RECOGNIZABLE=1; fi

if (( RECOGNIZABLE == 0 )); then
  cat >&2 <<'ERR_MSG'
[observed-errors-gate] BLOCKED: .claude/state/observed-errors.md exists
but doesn't contain anything that looks like a real error — no status
codes, no exceptions, no stack frames, no test failures.

The point of this gate is to force you to paste the verbatim symptom.
A summary like "the test failed" is not a captured error. Paste the
actual output your test/script/browser produced.

Override with OBSERVED_ERRORS_OVERRIDE="<reason>" if genuinely no
runtime symptom exists. Rule: ~/.claude/rules/observed-errors-first.md
ERR_MSG
  exit 1
fi

# All checks passed — allow the commit
exit 0
