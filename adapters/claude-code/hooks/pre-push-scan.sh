#!/bin/bash
# pre-push-scan.sh
#
# Scans the diff being pushed for credentials and sensitive identifiers.
# Blocks the push if any matches are found. Override with `git push --no-verify`.
#
# PATTERN SOURCES (loaded in order, all merged):
#   1. Built-in generic credential patterns (defined below, safe to commit)
#   2. ~/.claude/sensitive-patterns.local       — personal, never committed
#   3. ~/.claude/business-patterns.d/*.txt      — team-shared, loaded from
#      symlinks that point to cloned private repos (e.g., security-docs)
#
# FILE SAFELIST:
#   Any file whose basename is exactly `business-patterns.txt` is skipped
#   for content scanning. This lets teams store and share patterns files
#   in private repos without the scanner tripping on itself.
#
# INVOCATION:
#   - Used as a git pre-push hook (via ~/neural-lace/adapters/claude-code/git-hooks/pre-push
#     dispatcher, or direct per-repo symlink)
#   - Reads refs from stdin in git pre-push format:
#     <local_ref> <local_sha> <remote_ref> <remote_sha>

remote="$1"
url="$2"

if [ -z "$remote" ]; then
  exit 0
fi

ZERO_SHA="0000000000000000000000000000000000000000"

# ============================================================
# Built-in generic credential patterns (safe — no business specifics)
# ============================================================
# Format: DESCRIPTION|REGEX

BUILTIN_PATTERNS=(
  "GitHub personal access token|gh[pous]_[A-Za-z0-9]{36,255}"
  "GitHub app token|ghs_[A-Za-z0-9]{36,255}"
  "Anthropic API key|sk-ant-api[0-9]{2}-[A-Za-z0-9_-]{90,}"
  "OpenAI API key|sk-[A-Za-z0-9]{48}"
  "OpenAI project API key|sk-proj-[A-Za-z0-9_-]{60,}"
  "Stripe live secret key|sk_live_[0-9a-zA-Z]{24,}"
  "Stripe test secret key|sk_test_[0-9a-zA-Z]{24,}"
  "Stripe restricted key|rk_(live|test)_[0-9a-zA-Z]{24,}"
  "Slack bot token|xoxb-[0-9]{10,}-[0-9]{10,}-[A-Za-z0-9]{20,}"
  "Slack user token|xoxp-[0-9]{10,}-[0-9]{10,}-[0-9]{10,}-[A-Za-z0-9]{20,}"
  "AWS Access Key ID|AKIA[0-9A-Z]{16}"
  "AWS Secret Access Key|aws_secret_access_key[[:space:]]*[=:][[:space:]]*[\"']?[A-Za-z0-9/+=]{40}[\"']?"
  "Google API key|AIza[0-9A-Za-z_-]{35}"
  "Twilio Account SID|AC[a-f0-9]{32}"
  "Twilio Auth Token (heuristic)|twilio[_-]?auth[_-]?token[[:space:]]*[=:][[:space:]]*[\"']?[a-f0-9]{32}[\"']?"
  "SendGrid API key|SG\\.[A-Za-z0-9_-]{22}\\.[A-Za-z0-9_-]{43}"
  "Mailgun API key|key-[a-f0-9]{32}"
  "Generic bearer JWT|eyJ[A-Za-z0-9_-]{10,}\\.eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}"
  "PEM private key block|BEGIN (RSA |OPENSSH |DSA |EC |PGP )?PRIVATE KEY"
  "Supabase service role JWT (heuristic)|supabase[_-]?service[_-]?role[_-]?key[[:space:]]*[=:][[:space:]]*[\"']?eyJ"
)

# Sensitive filename patterns — block pushing these at all
SENSITIVE_FILE_PATTERNS=(
  "\\.env(\\.local|\\.production|\\.development|\\.test)?$"
  "credentials\\.json$"
  "secrets\\.yaml$"
  "secrets\\.yml$"
  "\\.pem$"
  "id_rsa$"
  "id_ed25519$"
  "\\.p12$"
  "\\.pfx$"
  "auth-state\\.json$"
)

# ============================================================
# Pattern loader: merge built-in + personal + team-shared
# ============================================================

ALL_PATTERNS=("${BUILTIN_PATTERNS[@]}")

load_patterns_from_file() {
  local file="$1"
  local source_label="$2"
  [ -f "$file" ] || return 0

  while IFS= read -r line; do
    # Skip comments and blank lines
    [ -z "$line" ] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # Prefix the description with the source for debugging
    local desc="${line%%|*}"
    local regex="${line#*|}"
    ALL_PATTERNS+=("[$source_label] $desc|$regex")
  done < "$file"
}

# 1. Personal patterns (per-machine, never committed)
load_patterns_from_file "$HOME/.claude/sensitive-patterns.local" "personal"

# 2a. Team-shared patterns via symlinks in .d/ dir
#     (preferred on macOS/Linux — updates flow via git pull automatically)
if [ -d "$HOME/.claude/business-patterns.d" ]; then
  for patterns_file in "$HOME/.claude/business-patterns.d"/*.txt; do
    [ -f "$patterns_file" ] || continue
    label=$(basename "$patterns_file" .txt)
    load_patterns_from_file "$patterns_file" "team:$label"
  done
fi

# 2b. Team-shared patterns via path pointer file
#     (preferred on Windows or when symlinks aren't practical)
#     ~/.claude/business-patterns.paths is a newline-separated list of
#     absolute paths to pattern files. Lines starting with # are comments.
POINTER_FILE="$HOME/.claude/business-patterns.paths"
if [ -f "$POINTER_FILE" ]; then
  while IFS= read -r path_line; do
    [ -z "$path_line" ] && continue
    [[ "$path_line" =~ ^[[:space:]]*# ]] && continue
    # Expand ~ and env vars
    expanded=$(eval echo "$path_line")
    if [ -f "$expanded" ]; then
      label=$(basename "$expanded" .txt)
      load_patterns_from_file "$expanded" "team:$label"
    fi
  done < "$POINTER_FILE"
fi

# ============================================================
# Safelist: file paths whose CONTENT is exempt from pattern scanning.
# (filename is still checked against sensitive filename patterns)
# ============================================================

is_content_scan_exempt() {
  local file="$1"
  local basename
  basename=$(basename "$file")

  # Any file named business-patterns.txt is a pattern definition — exempt
  if [ "$basename" = "business-patterns.txt" ]; then
    return 0
  fi

  # Example file in the neural-lace repo
  if [ "$basename" = "sensitive-patterns.local.example" ]; then
    return 0
  fi

  return 1
}

# ============================================================
# Main scan logic (per-file)
# ============================================================

BLOCKED=0
BLOCKED_REASONS=""

scan_file_content() {
  local range="$1"
  local file="$2"

  # Skip if exempt
  if is_content_scan_exempt "$file"; then
    return 0
  fi

  # Get the added lines only for this file (reduces false positives from context)
  local file_diff
  file_diff=$(git diff "$range" -- "$file" 2>/dev/null | grep -E "^\+" | grep -Ev "^\+\+\+" || echo "")

  [ -z "$file_diff" ] && return 0

  for entry in "${ALL_PATTERNS[@]}"; do
    local desc="${entry%%|*}"
    local regex="${entry#*|}"
    if echo "$file_diff" | grep -qE "$regex"; then
      local matched_line
      matched_line=$(echo "$file_diff" | grep -E "$regex" | head -1 | cut -c1-120)
      BLOCKED=1
      BLOCKED_REASONS+="
  [$file] $desc
    $matched_line"
    fi
  done
}

while read -r local_ref local_sha remote_ref remote_sha; do
  # Skip branch deletions
  if [ "$local_sha" = "$ZERO_SHA" ]; then
    continue
  fi

  # Determine diff range.
  # Git's "empty tree" SHA is used as the base for the very first commit.
  EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
  range=""
  range_is_single=""

  if [ "$remote_sha" = "$ZERO_SHA" ]; then
    # New branch being pushed. Find the oldest commit not yet on any remote.
    oldest=$(git rev-list "$local_sha" --not --remotes 2>/dev/null | tail -1)
    if [ -n "$oldest" ]; then
      # Check if that commit has a parent
      if git rev-parse --verify "${oldest}^" >/dev/null 2>&1; then
        range="${oldest}^..${local_sha}"
      else
        # First commit in the repo — use empty tree as base
        range="${EMPTY_TREE}..${local_sha}"
      fi
    else
      range="${EMPTY_TREE}..${local_sha}"
    fi
  else
    range="${remote_sha}..${local_sha}"
  fi

  # Files being added/modified
  files=$(git diff --name-only "$range" 2>/dev/null || echo "")

  # Scan each file
  for file in $files; do
    # Sensitive filename check (runs even on exempt files)
    for fpat in "${SENSITIVE_FILE_PATTERNS[@]}"; do
      if echo "$file" | grep -qE "$fpat"; then
        BLOCKED=1
        BLOCKED_REASONS+="
  [$file] sensitive filename pattern"
      fi
    done

    # Content scan (skipped on exempt files)
    scan_file_content "$range" "$file"
  done
done

# ============================================================
# Report + exit
# ============================================================

if [ "$BLOCKED" -eq 1 ]; then
  echo "" >&2
  echo "================================================================" >&2
  echo "PUSH BLOCKED: sensitive patterns detected" >&2
  echo "================================================================" >&2
  echo "$BLOCKED_REASONS" >&2
  echo "" >&2
  echo "Remote: $remote ($url)" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  1. Remove the sensitive content, amend/rewrite, then push again" >&2
  echo "  2. If you're CERTAIN this is a false positive:" >&2
  echo "       git push --no-verify" >&2
  echo "     (bypasses ALL pre-push checks — use sparingly)" >&2
  echo "" >&2
  echo "Patterns loaded from:" >&2
  echo "  - Built-in (generic credentials)" >&2
  [ -f "$HOME/.claude/sensitive-patterns.local" ] && \
    echo "  - ~/.claude/sensitive-patterns.local (personal)" >&2
  if [ -d "$HOME/.claude/business-patterns.d" ]; then
    for f in "$HOME/.claude/business-patterns.d"/*.txt; do
      [ -f "$f" ] && echo "  - $f (team)" >&2
    done
  fi
  echo "" >&2
  exit 1
fi

exit 0
