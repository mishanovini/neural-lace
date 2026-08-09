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

# ============================================================
# --self-test: fixture repo in mktemp -d; proves the allowlist scrub
# passes documented placeholders, still blocks real-shaped credentials
# (even beside a placeholder on one line), and still blocks sensitive
# filenames. Runs in seconds — the scan cost scales with range size.
# ============================================================
if [ "${1:-}" = "--self-test" ]; then
  export HARNESS_SELFTEST=1
  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  PASSED=0; FAILED=0
  _st() { # <label> <expected-rc> <actual-rc>
    if [ "$2" = "$3" ]; then echo "self-test ($1): PASS" >&2; PASSED=$((PASSED+1));
    else echo "self-test ($1): FAIL (expected rc $2, got $3)" >&2; FAILED=$((FAILED+1)); fi
  }
  TMPD="$(mktemp -d 2>/dev/null || mktemp -d -t ppscan)"
  trap 'rm -rf "$TMPD"' EXIT
  # Fixture commits use --no-verify: they run inside a throwaway mktemp
  # repo, and the global commit-time scanner must not decide these
  # scenarios — the unit under test is THIS hook's push-time verdict.
  ( cd "$TMPD" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --no-verify --allow-empty -m base ) || { echo "self-test: cannot build fixture repo" >&2; exit 1; }
  _scenario() { # <label> <expected-rc> <file> <content>
    ( cd "$TMPD" \
      && printf '%s\n' "$4" > "$3" \
      && git add "$3" \
      && git -c user.email=t@t -c user.name=t commit -q --no-verify -m "s: $1" \
      && echo "refs/heads/t $(git rev-parse HEAD) refs/heads/t $(git rev-parse HEAD~1)" \
         | bash "$SELF" origin fixture-url >/dev/null 2>&1 )
    _st "$1" "$2" "$?"
  }
  # FAKE_KEY is COMPOSED at runtime from adjacent string literals so no
  # source line of this file matches the AWS pattern — the push scanner
  # deliberately does NOT exempt scanner files (unlike pre-commit's
  # SAFE_FILES), keeping push-time as the strict last line of defense;
  # a literal here would block this file's own push
  # (review hcr-20260808-4edc4e8b finding 1).
  FAKE_KEY="AKIA""ABCDEFGHIJKLMNOP"
  _scenario "placeholder-only-allowed"      0 "a.txt" "docs use AKIAIOSFODNN7EXAMPLE as the example key"
  _scenario "real-shaped-key-blocked"       1 "b.txt" "leak: ${FAKE_KEY}"
  _scenario "key-beside-placeholder-blocked" 1 "c.txt" "both: ${FAKE_KEY} and AKIAIOSFODNN7EXAMPLE"
  _scenario "sensitive-filename-blocked"    1 ".env" "APP_MODE=prod"
  # Over-scrub guard (finding 2): a malicious/careless SHORT local
  # allowlist entry ("AKIA") must NOT neuter detection — the loader skips
  # it (with a WARN) and the real-shaped key still blocks.
  mkdir -p "$TMPD/home/.claude"
  printf 'AKIA\n' > "$TMPD/home/.claude/sensitive-patterns-allowlist.local"
  ( cd "$TMPD" \
    && printf '%s\n' "short-allowlist probe: ${FAKE_KEY}" > d.txt \
    && git add d.txt \
    && git -c user.email=t@t -c user.name=t commit -q --no-verify -m "s: over-scrub-guard" \
    && echo "refs/heads/t $(git rev-parse HEAD) refs/heads/t $(git rev-parse HEAD~1)" \
       | HOME="$TMPD/home" bash "$SELF" origin fixture-url >/dev/null 2>&1 )
  _st "short-allowlist-entry-cannot-neuter-detection" 1 "$?"
  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed" >&2
  [ "$FAILED" -gt 0 ] && exit 1
  exit 0
fi

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
# Documented-placeholder allowlist (2026-08-08, class:
# already-public-fixture-reflagged-on-branch-catch-up).
#
# These values are RESERVED BY THEIR VENDORS for documentation and can
# never be live credentials (AKIAIOSFODNN7EXAMPLE is AWS's published
# example Access Key ID). The repo uses them deliberately as secret-scan
# fixtures (tests/secret-backstop-fixture-check.sh,
# hooks/harness-hygiene-scan.sh) — see the archived plan
# docs/plans/archive/secret-scan-ci-backstop-skip.md, which gave the CI
# backstop the same exemption. Without this, any stale branch whose
# catch-up range re-adds those already-public files blocks its own backup
# push (observed 2026-08-08: a 19-branch backup push blocked after a
# 119-minute scan on exactly these three fixture files).
#
# Semantics: SCRUB-THEN-RETEST, not line-skip — allowlisted values are
# replaced with a sentinel and the pattern re-tested, so a line carrying
# BOTH a placeholder and a real credential still blocks.
# Extend per-machine via ~/.claude/sensitive-patterns-allowlist.local
# (one exact value per line, # comments allowed).
# ============================================================

ALLOWLIST_VALUES=(
  "AKIAIOSFODNN7EXAMPLE"
  "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
)

if [ -f "$HOME/.claude/sensitive-patterns-allowlist.local" ]; then
  while IFS= read -r av_line; do
    av_line="${av_line%$'\r'}"
    [ -z "$av_line" ] && continue
    [[ "$av_line" =~ ^[[:space:]]*# ]] && continue
    # Over-scrub guard (review hcr-20260808-4edc4e8b finding 2): a short
    # entry like "AKIA" would scrub the shared prefix out of REAL
    # credentials and silently disable the whole pattern class. Skip
    # loudly instead of loading.
    if [ "${#av_line}" -lt 16 ]; then
      echo "[pre-push-scan] WARN: allowlist entry shorter than 16 chars SKIPPED (over-scrub guard): '${av_line}'" >&2
      continue
    fi
    ALLOWLIST_VALUES+=("$av_line")
  done < "$HOME/.claude/sensitive-patterns-allowlist.local"
fi

# scrub_allowlisted <line> — prints the line with every allowlisted value
# replaced by a sentinel that matches no credential pattern.
scrub_allowlisted() {
  local line="$1" v
  for v in "${ALLOWLIST_VALUES[@]}"; do
    line="${line//"$v"/<DOC-PLACEHOLDER>}"
  done
  printf '%s\n' "$line"
}

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

# ============================================================
# SINGLE-PASS content scan (2026-08-08 performance rewrite).
#
# The previous implementation spawned `git diff <range> -- <file>` PER
# FILE and then ran every pattern as its own grep PER FILE — thousands
# of subprocesses on a large catch-up range. Measured cost: 119m46s for
# one 19-branch backup push, and leaked hook processes accumulated
# 16-23 CPU-HOURS each when their git parent died mid-push. This pass
# runs ONE `git diff` for the whole range, tags every added line with
# its file, and runs ONE combined-alternation grep over the stream;
# the per-pattern loop (for attribution + scrub-then-retest) runs only
# on the rare lines the combined grep already matched.
#
# Block/allow parity with the old code: a push is blocked iff some
# added line of a non-exempt file still matches some pattern after
# placeholder-scrubbing — identical decision rule, ~100x fewer
# subprocesses.
# ============================================================

# Combined alternation of every pattern, built once. Each pattern is
# wrapped in (...) so alternation cannot bleed across patterns.
COMBINED_REGEX=""
for entry in "${ALL_PATTERNS[@]}"; do
  COMBINED_REGEX="${COMBINED_REGEX:+$COMBINED_REGEX|}(${entry#*|})"
done

# scan_range_content <range> <ref-label>
# Emits BLOCKED/BLOCKED_REASONS for every (file, pattern) pair with a
# surviving match in the range's added lines. The ref label rides the
# report so a multi-ref push names WHICH ref carried the hit
# (previously only the file was named — a 19-ref block forced manual
# per-branch range replication to find the culprit).
scan_range_content() {
  local range="$1" ref_label="$2"
  # "file<TAB>+line" for every added line; f reset on /dev/null so
  # deleted-file hunks cannot inherit the previous filename. Streamed to
  # a TEMP FILE, never a bash variable: capturing a 30MB range diff in a
  # variable measured ~10s per shuffle on MSYS and strips null bytes.
  local tagged_file
  tagged_file="$(mktemp 2>/dev/null || mktemp -t ppscan-tagged)"
  git diff "$range" 2>/dev/null \
    | awk '/^\+\+\+ \/dev\/null/{f=""} /^\+\+\+ b\//{f=substr($0,7)} /^\+/ && !/^\+\+\+/{if (f!="") print f "\t" $0}' \
    > "$tagged_file"

  local hits
  hits=$(grep -aE "$COMBINED_REGEX" "$tagged_file" || true)
  rm -f "$tagged_file"
  [ -z "$hits" ] && return 0

  local seen=""
  local mfile mline scrubbed entry desc regex
  while IFS=$'\t' read -r mfile mline; do
    [ -z "$mfile" ] && continue
    if is_content_scan_exempt "$mfile"; then
      continue
    fi
    scrubbed=$(scrub_allowlisted "$mline")
    for entry in "${ALL_PATTERNS[@]}"; do
      desc="${entry%%|*}"
      regex="${entry#*|}"
      if printf '%s\n' "$scrubbed" | grep -qE "$regex"; then
        # one report line per (file, pattern) pair, like the old output
        case "$seen" in *"|$mfile|$desc|"*) continue ;; esac
        seen="${seen}|$mfile|$desc|"
        BLOCKED=1
        BLOCKED_REASONS+="
  [$mfile] $desc (ref: ${ref_label})
    $(printf '%s' "$mline" | cut -c1-120)"
      fi
    done
  done <<< "$hits"
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

  # Sensitive filename check (runs even on exempt files). Pure-bash
  # [[ =~ ]] on purpose: the old `echo | grep` pair spawned TWO processes
  # per (file, pattern) — 11,400 spawns on a 1,140-file range, ~20-40
  # minutes on MSYS where process spawn costs ~50-100ms (the dominant
  # cost of the measured 119m scan; the same script is fast on Linux CI,
  # which is why the cost hid). bash regex is ERE, same dialect.
  for file in $files; do
    for fpat in "${SENSITIVE_FILE_PATTERNS[@]}"; do
      if [[ "$file" =~ $fpat ]]; then
        BLOCKED=1
        BLOCKED_REASONS+="
  [$file] sensitive filename pattern (ref: ${local_ref})"
      fi
    done
  done

  # Content scan — single pass over the whole range (exempt files are
  # skipped per matched line inside scan_range_content)
  scan_range_content "$range" "$local_ref"
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
  echo "This gate: ~/.claude/hooks/pre-push-scan.sh (source: adapters/claude-code/hooks/pre-push-scan.sh)" >&2
  exit 1
fi

exit 0
