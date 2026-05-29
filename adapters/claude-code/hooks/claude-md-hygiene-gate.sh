#!/bin/bash
# claude-md-hygiene-gate.sh — Hygiene-2 PR 3 (Component 2)
#
# PreToolUse hook (Bash matcher) that scans `git commit` invocations
# touching `adapters/claude-code/CLAUDE.md` for content-architecture
# violations that would re-introduce the bloat the harness-hygiene-2
# initiative was set up to defend against.
#
# Three detection checks (per Component 2 of harness-hygiene-2):
#   1. SIZE — CLAUDE.md grows past the soft 200-line ceiling
#   2. RULE-BODY SHAPE — added content matches rule-body patterns
#      (multi-line numbered lists, `Rule X:` headers, paragraph blocks
#      >5 lines without a `rules/<name>.md` pointer)
#   3. DUPLICATION — added content contains 5+ consecutive matching
#      words with any existing `rules/*.md` file (signals body-of-rule
#      duplication that should be a pointer instead)
#
# Companion to:
#   - rules/information-architecture.md (the doctrine this defends)
#   - hooks/session-start-discovery-cheatsheet.sh (sibling Component 4)
#   - hooks/principles-compliance-gate.sh CRED detection (sibling Component 3)
#
# MODE
#   warn  (default) — emit findings to stderr, exit 0 (never blocks)
#   block          — exit 2 on any finding (after calibration)
# Resolution order: CLAUDE_MD_HYGIENE_MODE env > ~/.claude/local/claude-md-hygiene-mode > "warn"
#
# Initial posture (per the user spec): warn-mode only. Flip to block
# after 24 hours of calibration data on the warn-log.
#
# Trigger: PreToolUse Bash. The hook itself extracts the command from
# `CLAUDE_TOOL_INPUT` JSON and skips unless the command is `git commit`
# (NOT `git commit-tree`) AND `adapters/claude-code/CLAUDE.md` is in
# the staged diff (via `git diff --cached --name-only`).
#
# ESCAPE HATCH
#   CLAUDE_MD_HYGIENE_DISABLE=1   — no-op (harness-dev sessions that edit
#                                   the gate's own fixtures, etc.)
#
# SELF-TEST
#   claude-md-hygiene-gate.sh --self-test
#
# EXIT CODES
#   0 — allowed (always, in warn-mode; or no findings in block-mode)
#   1 — internal error (jq missing, etc.) — fail-open
#   2 — blocked (block-mode only, ≥1 finding)

set -u

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
SIZE_THRESHOLD="${CLAUDE_MD_HYGIENE_SIZE_THRESHOLD:-200}"
DUPLICATION_MIN_RUN="${CLAUDE_MD_HYGIENE_DUP_MIN_WORDS:-5}"
TARGET_PATH="${CLAUDE_MD_HYGIENE_TARGET:-adapters/claude-code/CLAUDE.md}"

# ----------------------------------------------------------------------------
# Detection core — operates on (1) the post-commit file content and
# (2) the added-lines diff. Returns counts via globals FIND_SIZE,
# FIND_RULE_BODY, FIND_DUPLICATION, and appends human-readable lines to
# FINDINGS.
# ----------------------------------------------------------------------------
detect_hygiene_violations() {
  local file_content="$1"
  local added_lines="$2"
  local rules_dir="$3"
  FIND_SIZE=0; FIND_RULE_BODY=0; FIND_DUPLICATION=0
  FINDINGS=""

  # --- 1. SIZE check ---
  local line_count
  line_count=$(printf '%s' "$file_content" | grep -c '' 2>/dev/null || echo 0)
  if [[ "$line_count" -gt "$SIZE_THRESHOLD" ]]; then
    FIND_SIZE=1
    FINDINGS+="SIZE: CLAUDE.md is $line_count lines (soft ceiling $SIZE_THRESHOLD). Extract bodies into rules/<name>.md and leave one-line pointers behind. See rules/information-architecture.md \"What CLAUDE.md is FOR.\""$'\n'
  fi

  # --- 2. RULE-BODY SHAPE check (on added lines only) ---
  # Look for multi-line numbered lists OR `Rule N:` headers OR paragraph
  # blocks >5 lines that don't contain a `rules/.*\.md` pointer.
  if [[ -n "$added_lines" ]]; then
    # 2a: Added "Rule N — description" style headers (rule-body shape)
    local rule_header_hits
    rule_header_hits=$(printf '%s\n' "$added_lines" | grep -cE '^\+\*?\*?Rule [0-9]+ ?[—:-]' 2>/dev/null | head -n 1 | tr -dc '0-9')
    [[ -z "$rule_header_hits" ]] && rule_header_hits=0
    if [[ "$rule_header_hits" -gt 0 ]]; then
      FIND_RULE_BODY=$((FIND_RULE_BODY+1))
      FINDINGS+="RULE-BODY: Added $rule_header_hits 'Rule N — ...' header(s) in CLAUDE.md. Rule bodies belong in rules/<name>.md; CLAUDE.md should carry one-line pointers."$'\n'
    fi

    # 2b: Added "- **Rule N — ...**" bullet headers (the principles.md inline form)
    local rule_bullet_hits
    rule_bullet_hits=$(printf '%s\n' "$added_lines" | grep -cE '^\+- \*\*Rule [0-9]+' 2>/dev/null | head -n 1 | tr -dc '0-9')
    [[ -z "$rule_bullet_hits" ]] && rule_bullet_hits=0
    if [[ "$rule_bullet_hits" -gt 3 ]]; then
      # >3 means it's a list of rule bodies, not a one-line summary
      FIND_RULE_BODY=$((FIND_RULE_BODY+1))
      FINDINGS+="RULE-BODY: Added $rule_bullet_hits '- **Rule N**' bullets in CLAUDE.md. If duplicating principles.md content, replace with a single @-reference."$'\n'
    fi

    # 2c: Long added-paragraph runs (>5 added lines in a row with no `rules/...md` pointer)
    local long_run_hits=0
    local current_run=0
    local has_pointer=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^\+ ]] && [[ ! "$line" =~ ^\+\+\+ ]]; then
        current_run=$((current_run+1))
        # Check if this added line names a rules/*.md pointer
        if printf '%s' "$line" | grep -qE 'rules/[a-z0-9-]+\.md|`rules/' 2>/dev/null; then
          has_pointer=1
        fi
      else
        if [[ "$current_run" -gt 5 ]] && [[ "$has_pointer" -eq 0 ]]; then
          long_run_hits=$((long_run_hits+1))
        fi
        current_run=0
        has_pointer=0
      fi
    done <<< "$added_lines"
    # Tail check (run ends at EOF)
    if [[ "$current_run" -gt 5 ]] && [[ "$has_pointer" -eq 0 ]]; then
      long_run_hits=$((long_run_hits+1))
    fi
    if [[ "$long_run_hits" -gt 0 ]]; then
      FIND_RULE_BODY=$((FIND_RULE_BODY+1))
      FINDINGS+="RULE-BODY: Added $long_run_hits paragraph block(s) longer than 5 lines without naming a rules/<name>.md pointer. This looks like rule-body content; consider extracting to rules/<name>.md."$'\n'
    fi
  fi

  # --- 3. DUPLICATION check (added lines vs. each rules/*.md) ---
  # For each added line of substantive length (>40 chars), check whether
  # it appears verbatim (case-insensitive) in any rules/*.md file.
  if [[ -n "$added_lines" ]] && [[ -d "$rules_dir" ]]; then
    local dup_count=0
    local dup_files=""
    local first_substantive=""
    while IFS= read -r line; do
      [[ "$line" =~ ^\+ ]] || continue
      [[ "$line" =~ ^\+\+\+ ]] && continue
      # Strip leading '+'
      local body="${line#+}"
      # Strip leading/trailing whitespace
      body="$(printf '%s' "$body" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      # Only consider lines with > DUPLICATION_MIN_RUN words AND > 40 chars
      local word_count
      word_count=$(printf '%s' "$body" | wc -w | tr -d '[:space:]')
      if [[ "${#body}" -lt 40 ]]; then continue; fi
      if [[ "$word_count" -lt "$DUPLICATION_MIN_RUN" ]]; then continue; fi
      # Skip lines that are obviously @-references or backtick-pointer lines
      if printf '%s' "$body" | grep -qE '^@~/\.claude/|^`[^`]+`$|^- `[a-z0-9-]+\.md`' 2>/dev/null; then continue; fi
      # Build a sliding-window of N consecutive words from the body. If any
      # window matches verbatim in any rules/*.md, count as duplication.
      # This catches "body of an existing rule body is substantial enough"
      # style fragments without requiring exact-line match.
      local words_arr=()
      # shellcheck disable=SC2206
      words_arr=( $body )
      local n_words="${#words_arr[@]}"
      local i j window matched_basename=""
      for ((i=0; i + DUPLICATION_MIN_RUN <= n_words; i++)); do
        window=""
        for ((j=0; j < DUPLICATION_MIN_RUN; j++)); do
          window+="${words_arr[$((i+j))]} "
        done
        window="${window% }"
        # Skip very-short windows (defensive)
        [[ "${#window}" -lt 25 ]] && continue
        local rule_file
        for rule_file in "$rules_dir"/*.md; do
          [[ -f "$rule_file" ]] || continue
          local basename
          basename=$(basename "$rule_file")
          [[ "$basename" == "INDEX.md" ]] && continue
          if grep -F -q -- "$window" "$rule_file" 2>/dev/null; then
            matched_basename="$basename"
            break
          fi
        done
        [[ -n "$matched_basename" ]] && break
      done
      if [[ -n "$matched_basename" ]]; then
        dup_count=$((dup_count+1))
        [[ -z "$first_substantive" ]] && first_substantive="$body"
        if [[ "$dup_files" != *"$matched_basename"* ]]; then
          dup_files+="$matched_basename "
        fi
      fi
    done <<< "$added_lines"
    if [[ "$dup_count" -gt 0 ]]; then
      FIND_DUPLICATION="$dup_count"
      local snippet="${first_substantive:0:80}"
      [[ "${#first_substantive}" -gt 80 ]] && snippet+="..."
      FINDINGS+="DUPLICATION: $dup_count added line(s) duplicate content in [${dup_files% }]. CLAUDE.md should point at canonical rule files, not duplicate their bodies. First match: \"$snippet\""$'\n'
    fi
  fi
}

# ----------------------------------------------------------------------------
# --self-test — inline fixtures, no external files
# ----------------------------------------------------------------------------
if [[ "${1:-}" = "--self-test" ]]; then
  PASS=0; FAIL=0
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t cmhgsf)
  # shellcheck disable=SC2064
  trap "rm -rf '$TMP'" EXIT

  # Create a minimal rules/ fixture for the duplication test
  RULES_FIXTURE="$TMP/rules"
  mkdir -p "$RULES_FIXTURE"
  cat > "$RULES_FIXTURE/existing-rule.md" <<'EOF'
# Existing Rule

This is the canonical body of an existing rule. The body is substantial enough to be detected if duplicated elsewhere.

When you find yourself reading this content in another file, that other file is duplicating the canonical body and should reference this rule file instead.
EOF
  cat > "$RULES_FIXTURE/INDEX.md" <<'EOF'
# Rules INDEX
EOF

  check() {
    local name="$1"; shift
    local expect_size="$1"; shift
    local expect_rule_body="$1"; shift
    local expect_dup_nonzero="$1"; shift
    local file_content="$1"; shift
    local added_lines="$1"
    detect_hygiene_violations "$file_content" "$added_lines" "$RULES_FIXTURE"
    local ok=1
    if [[ "$expect_size" -ne "$FIND_SIZE" ]]; then ok=0; fi
    if [[ "$expect_rule_body" -ne "$FIND_RULE_BODY" ]]; then ok=0; fi
    local dup_observed=0
    [[ "$FIND_DUPLICATION" -gt 0 ]] && dup_observed=1
    if [[ "$expect_dup_nonzero" -ne "$dup_observed" ]]; then ok=0; fi
    if [[ "$ok" -eq 1 ]]; then
      echo "PASS  $name (size=$FIND_SIZE rule_body=$FIND_RULE_BODY dup=$FIND_DUPLICATION)"
      PASS=$((PASS+1))
    else
      echo "FAIL  $name (expected size=$expect_size rule_body=$expect_rule_body dup_nonzero=$expect_dup_nonzero; got size=$FIND_SIZE rule_body=$FIND_RULE_BODY dup=$FIND_DUPLICATION)"
      FAIL=$((FAIL+1))
    fi
  }

  # Scenario 1: clean small CLAUDE.md, no findings
  CLEAN_CONTENT="$(printf 'line %s\n' {1..50})"
  check "s1 clean under threshold" 0 0 0 "$CLEAN_CONTENT" ""

  # Scenario 2: CLAUDE.md > threshold (size warn)
  BIG_CONTENT="$(printf 'line %s\n' {1..250})"
  check "s2 size threshold exceeded" 1 0 0 "$BIG_CONTENT" ""

  # Scenario 3: rule-body shape added (Rule N — header)
  RULE_BODY_ADDED='+## Operating Principles
+
+**Rule 8 — Always test rigorously.** This is the new rule body that
+adds substantive content describing what should be done and when,
+with examples and edge cases that really belong in a rules/*.md file.'
  check "s3 rule-body shape detected" 0 1 0 "$CLEAN_CONTENT" "$RULE_BODY_ADDED"

  # Scenario 4: duplication of existing rule body
  DUPLICATE_ADDED='+This is the canonical body of an existing rule. The body is substantial enough to be detected if duplicated elsewhere.'
  check "s4 duplication detected" 0 0 1 "$CLEAN_CONTENT" "$DUPLICATE_ADDED"

  # Scenario 5: pointer-form added (NOT flagged as duplication)
  POINTER_ADDED='+- `existing-rule.md` — see this rule for the canonical body and its enforcement.'
  check "s5 pointer-form not flagged as duplication" 0 0 0 "$CLEAN_CONTENT" "$POINTER_ADDED"

  # Scenario 6: long added paragraph WITH a rules/ pointer (not flagged)
  WITH_POINTER='+This is a long substantive paragraph that goes on for many lines
+and accumulates a lot of content describing harness behavior in
+great detail with many sentences and lots of explanatory prose
+covering edge cases and corner cases and how the mechanism works
+but it explicitly names a `rules/example-rule.md` pointer near the
+end so the gate should NOT flag it as orphaned rule-body content.'
  check "s6 long para WITH rules pointer exempt" 0 0 0 "$CLEAN_CONTENT" "$WITH_POINTER"

  # Scenario 7: combined — big AND duplicated AND rule-shape
  COMBINED_ADDED='+**Rule 9 — Yet another rule.** This is the canonical body of an existing rule. The body is substantial enough to be detected if duplicated elsewhere.'
  check "s7 combined: size+rule-body+dup" 1 1 1 "$BIG_CONTENT" "$COMBINED_ADDED"

  echo ""
  echo "Result: $PASS passed, $FAIL failed"
  [[ "$FAIL" -gt 0 ]] && exit 1
  exit 0
fi

# ----------------------------------------------------------------------------
# Live path
# ----------------------------------------------------------------------------

# Escape hatch
if [[ "${CLAUDE_MD_HYGIENE_DISABLE:-0}" = "1" ]]; then
  exit 0
fi

# Read tool input (Claude Code PreToolUse hook contract)
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
if [[ -z "$INPUT" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Extract the command — should be Bash
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
if [[ -z "$CMD" ]]; then
  exit 0
fi

# Only fire on `git commit` (NOT git commit-tree)
if ! echo "$CMD" | grep -qE '(^|[[:space:];&|])git[[:space:]]+commit([[:space:]]|$)' 2>/dev/null; then
  exit 0
fi
if echo "$CMD" | grep -qE 'git[[:space:]]+commit-tree' 2>/dev/null; then
  exit 0
fi

# Locate repo root (handle worktrees)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
[[ -z "$REPO_ROOT" ]] && exit 0

# Resolve target path
TARGET="$REPO_ROOT/$TARGET_PATH"
if [[ ! -f "$TARGET" ]]; then
  exit 0
fi

# Only fire if CLAUDE.md is in the staged diff
STAGED_LIST=$(git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null || echo "")
if ! echo "$STAGED_LIST" | grep -qF "$TARGET_PATH" 2>/dev/null; then
  exit 0
fi

# Resolve mode
MODE="${CLAUDE_MD_HYGIENE_MODE:-}"
if [[ -z "$MODE" ]] && [[ -f "$HOME/.claude/local/claude-md-hygiene-mode" ]]; then
  MODE=$(tr -d '[:space:]' < "$HOME/.claude/local/claude-md-hygiene-mode" 2>/dev/null || echo "")
fi
[[ -z "$MODE" ]] && MODE="warn"
[[ "$MODE" != "block" ]] && MODE="warn"

# Read CLAUDE.md content (post-commit state — the working-tree file)
FILE_CONTENT=$(cat "$TARGET" 2>/dev/null || echo "")

# Read added lines from staged diff
ADDED_LINES=$(git -C "$REPO_ROOT" diff --cached -- "$TARGET_PATH" 2>/dev/null || echo "")

# Locate rules dir
RULES_DIR="$REPO_ROOT/adapters/claude-code/rules"
[[ ! -d "$RULES_DIR" ]] && exit 0

detect_hygiene_violations "$FILE_CONTENT" "$ADDED_LINES" "$RULES_DIR"

TOTAL=$((FIND_SIZE + FIND_RULE_BODY + FIND_DUPLICATION))

# Always emit machine-readable summary
echo "[claude-md-hygiene] mode=$MODE size=$FIND_SIZE rule_body=$FIND_RULE_BODY duplication=$FIND_DUPLICATION total=$TOTAL" >&2

# Log findings
LOG_FILE="${CLAUDE_MD_HYGIENE_LOG:-$HOME/.claude/state/claude-md-hygiene-warnings.log}"
if [[ "$TOTAL" -gt 0 ]]; then
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    printf '%s | mode=%s | %s\n' "$TS" "$MODE" "$f" >> "$LOG_FILE" 2>/dev/null || true
  done <<< "$FINDINGS"
fi

# Emit findings to stderr (always)
if [[ "$TOTAL" -gt 0 ]]; then
  echo "[claude-md-hygiene] findings on $TARGET_PATH:" >&2
  printf '%s' "$FINDINGS" | sed 's/^/  /' >&2
  echo "[claude-md-hygiene] see rules/information-architecture.md for guidance. Suppress with CLAUDE_MD_HYGIENE_DISABLE=1." >&2
fi

# Warn-mode never blocks; block-mode exits 2 on any finding
if [[ "$MODE" = "warn" ]]; then
  exit 0
fi

if [[ "$TOTAL" -gt 0 ]]; then
  exit 2
fi

exit 0
