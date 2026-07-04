#!/bin/bash
# definition-on-first-use-gate.sh — Phase 1d-F (Decision 023), 2026-05-04
#
# DEMOTED to non-blocking warn at NL Overhaul Wave D.6 (§D.0.4 / §D.6
# item 8, 2026-07-02): the path that used to `exit 1` (block) now exits
# 0 and instead emits a hookSpecificOutput.additionalContext warn (the
# sanctioned channel that reaches model context) plus a signal-ledger
# `warn` event. Detection logic is UNCHANGED — only the verdict emission
# changed from block to warn. manifest.json's `blocking` flag for this
# unit flips to false in the same wave (D.5 template/manifest cutover).
# --self-test scenarios 4 and 7 (previously asserting block/exit=1) are
# updated to assert the warn-shape (exit=0 + warn text on stderr).
#
# PreToolUse hook (Bash matcher) that used to block `git commit` when the
# commit stages `*.md` files under `neural-lace/build-doctrine/` and any
# newly-added acronym (regex \b[A-Z]{2,6}\b minus stopword allowlist) is
# neither in the glossary nor defined in-context within the same diff;
# now warns instead.
#
# Rule (Decision 023):
#   - 023a: Acronym detection via \b[A-Z]{2,6}\b (2-6 char bound).
#   - 023b: Stopword allowlist for universally-understood tokens.
#   - 023c: Scope-prefix is `neural-lace/build-doctrine/**/*.md`.
#   - 023d: "Defined" = in glossary (`**TERM**`, `## TERM`, `### TERM`,
#           `| TERM |`) OR parenthetical-in-diff `<TERM>\s*\(<2+ words>\)`
#           within ~30 chars of first occurrence.
#   - 023e: On block, stderr names the term + remediation paths.
#
# Glossary path resolution:
#   1. ~/claude-projects/Build Doctrine/outputs/glossary.md
#   2. ${REPO}/build-doctrine/outputs/glossary.md
#   3. If neither exists: emit warning, ALLOW.
#
# Trigger:
#   PreToolUse on tool_name == "Bash". Detects `git commit` (after stripping
#   leading `cd …` and `&&`-prefixed segments). Pass-through on non-Bash
#   and non-commit Bash commands.
#
# Exit codes:
#   0 — allow (always, post-demotion; a WARN may be emitted via
#       hookSpecificOutput.additionalContext + a signal-ledger entry)
#   2 — internal error (passes through to allow; we don't lock up the session)

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/signal-ledger.sh
source "$SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true

# ============================================================
# Stopword allowlist (Decision 023b)
# Space-separated. Compared case-sensitively (uppercase only).
# ============================================================
STOPWORDS=(
  OK OR AND IF IS OF BY IN ON AT TO THE A
  WHO WHAT WHERE WHEN WHY HOW
  JSON YAML TOML MD PDF PNG JPG GIF SVG XML CSV TSV
  URL URI HTTP HTTPS FTP SSH TLS SSL DNS
  API CLI GUI UI UX CSS HTML JS TS SQL
  ID IDS IP CPU GPU RAM ROM USB DVD CD
  PR PRS CI CD QA RC OS
)

_is_stopword() {
  local term="$1"
  local sw
  for sw in "${STOPWORDS[@]}"; do
    if [[ "$term" == "$sw" ]]; then
      return 0
    fi
  done
  return 1
}

# ============================================================
# Glossary path resolution
# Returns the path to the glossary file on stdout, OR empty string
# if neither candidate exists. Always exits 0.
# ============================================================
_resolve_glossary() {
  local repo_root="$1"
  local p1="$HOME/claude-projects/Build Doctrine/outputs/glossary.md"
  local p2="$repo_root/build-doctrine/outputs/glossary.md"
  if [[ -f "$p1" ]]; then
    printf '%s' "$p1"
    return 0
  fi
  if [[ -f "$p2" ]]; then
    printf '%s' "$p2"
    return 0
  fi
  printf ''
  return 0
}

# ============================================================
# Check if term is defined in glossary file
# Recognized formats: **TERM**, ## TERM, ### TERM, | TERM |
# Returns 0 if defined, 1 if not.
# ============================================================
_in_glossary() {
  local term="$1"
  local glossary="$2"
  [[ -z "$glossary" ]] && return 1
  [[ ! -f "$glossary" ]] && return 1
  # Bold inline: **TERM** (with optional surrounding whitespace, end-of-bold)
  if grep -qE "\*\*${term}\*\*" "$glossary" 2>/dev/null; then
    return 0
  fi
  # Heading: ## TERM or ### TERM (followed by space, em-dash, hyphen, or end-of-line)
  if grep -qE "^#{2,3} ${term}([[:space:]]|$|—|-)" "$glossary" 2>/dev/null; then
    return 0
  fi
  # Table cell: | TERM | (left-padded)
  if grep -qE "^\| ${term} \|" "$glossary" 2>/dev/null; then
    return 0
  fi
  return 1
}

# ============================================================
# Check if term is defined in-diff via parenthetical
# Looks for: <TERM>\s*\(.{2,40}\) where the parenthetical contains 2+ words
# Args: $1 = term, $2 = full diff content (added lines)
# Returns 0 if defined-in-diff, 1 if not.
# ============================================================
_in_diff_definition() {
  local term="$1"
  local diff_content="$2"
  # Find lines containing TERM ( ... ) where parenthetical has 2+ words
  # Use awk for the multi-step check.
  printf '%s\n' "$diff_content" | awk -v t="$term" '
    {
      # Search for TERM\s*\(...\)
      pattern = t "[[:space:]]*\\(([^)]+)\\)"
      if (match($0, pattern, a)) {
        paren = a[1]
        # Count words: split on whitespace, count non-empty
        n = split(paren, words, /[[:space:]]+/)
        wc = 0
        for (i=1; i<=n; i++) if (words[i] != "") wc++
        if (wc >= 2) {
          found = 1
          exit
        }
      }
    }
    END { if (found) exit 0; else exit 1 }
  '
  return $?
}

# ============================================================
# Extract added-line acronyms from a unified diff for a single file
# Args: $1 = file path (in-scope), $2 = repo root
# Outputs unique acronyms (one per line) to stdout, sorted, deduplicated.
# ============================================================
_extract_acronyms() {
  local file="$1"
  local repo_root="$2"
  # Get added lines from the staged diff for this file
  git -C "$repo_root" diff --cached -- "$file" 2>/dev/null \
    | awk '/^\+/ && !/^\+\+\+/ { sub(/^\+/, ""); print }' \
    | grep -oE '\b[A-Z]{2,6}\b' \
    | sort -u
}

# ============================================================
# Get full added-line content for a file (used for in-diff definition lookup)
# Args: $1 = file path, $2 = repo root
# Outputs raw added-line content to stdout.
# ============================================================
_added_lines() {
  local file="$1"
  local repo_root="$2"
  git -C "$repo_root" diff --cached -- "$file" 2>/dev/null \
    | awk '/^\+/ && !/^\+\+\+/ { sub(/^\+/, ""); print }'
}

# ============================================================
# --self-test handler
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF_TEST_HOOK" ]]; then
    echo "self-test: cannot resolve own path" >&2
    exit 2
  fi

  PASSED=0
  FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t defon-firstuse)
  if [[ -z "$TMPROOT" ]] || [[ ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  # Helper: build a synthetic repo with optional in-scope file content +
  # optional glossary, then invoke the hook against synthesized PreToolUse
  # Bash JSON for git commit. Returns hook's exit code.
  #
  # Args: $1 = scenario label
  #       $2 = in-scope file content (empty = don't create the file)
  #       $3 = glossary file content (empty = no glossary)
  #       $4 = optional out-of-scope file content (empty = none)
  _run_scenario() {
    local label="$1"
    local in_scope_content="$2"
    local glossary_content="$3"
    local out_scope_content="${4:-}"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo/neural-lace/build-doctrine"
    mkdir -p "$repo/build-doctrine/outputs"
    (
      cd "$repo" || exit 99
      git init -q 2>/dev/null || true
      git config core.hooksPath "" 2>/dev/null  # don't fire machine-global harness git hooks in fixtures
      git config user.email "test@example.com" 2>/dev/null
      git config user.name "Test" 2>/dev/null
      git config commit.gpgsign false 2>/dev/null

      # Initial commit so HEAD exists
      echo "init" > .gitkeep
      git add .gitkeep 2>/dev/null
      git commit -q -m "init" 2>/dev/null

      if [[ -n "$glossary_content" ]]; then
        printf '%s' "$glossary_content" > "build-doctrine/outputs/glossary.md"
        git add "build-doctrine/outputs/glossary.md" 2>/dev/null
      fi

      if [[ -n "$in_scope_content" ]]; then
        printf '%s' "$in_scope_content" > "neural-lace/build-doctrine/test-doc.md"
        git add "neural-lace/build-doctrine/test-doc.md" 2>/dev/null
      fi

      if [[ -n "$out_scope_content" ]]; then
        mkdir -p docs
        printf '%s' "$out_scope_content" > "docs/random.md"
        git add "docs/random.md" 2>/dev/null
      fi

      # The hook resolves glossary via $HOME first; we want the in-repo
      # fallback path to be exercised for self-test isolation. We override
      # HOME for this subshell to a non-existent path so resolution falls
      # through to the repo-local fallback.
      HOME="$repo/no-such-home" \
        bash -c '
          input='\''{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'\''
          printf %s "$input" | bash "'"$SELF_TEST_HOOK"'" >stdout.txt 2>stderr.txt
          echo $? > rc.txt
        '
    )
    cat "$repo/rc.txt" 2>/dev/null || echo 99
  }

  # ---- Test fixtures ----

  GLOSSARY_BASIC='# Glossary

**LLM** — Large language model.
**PRD** — Product Requirements Document.

## Section

**ADR** — Architectural Decision Record.
'

  IN_SCOPE_DEFINED_GLOSSARY='# Doc

The LLM subsystem handles inference. The PRD captures requirements.
'

  IN_SCOPE_DEFINED_DIFF='# Doc

The XYZ (cross-system Y zone) component routes traffic between regions.
'

  IN_SCOPE_UNDEFINED='# Doc

The QQQ subsystem manages caching across availability zones.
'

  IN_SCOPE_STOPWORD_ONLY='# Doc

The URL points to a JSON file. The HTTP API returns CSV format.
'

  OUT_OF_SCOPE_UNDEFINED='# Random doc

The ZZZ system has undefined acronyms but is not in scope.
'

  IN_SCOPE_DIFF_SINGLE_WORD_PAREN='# Doc

The XYZ (alias) component routes traffic.
'

  # ---- Scenario 1: PASS — no in-scope changes, only out-of-scope file ----
  RC=$(_run_scenario s1 "" "$GLOSSARY_BASIC" "$OUT_OF_SCOPE_UNDEFINED")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (1) PASS-no-in-scope-changes: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (1) PASS-no-in-scope-changes: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s1/stderr.txt" 2>/dev/null >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 2: PASS — acronym defined in glossary ----
  RC=$(_run_scenario s2 "$IN_SCOPE_DEFINED_GLOSSARY" "$GLOSSARY_BASIC")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (2) PASS-defined-in-glossary: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (2) PASS-defined-in-glossary: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s2/stderr.txt" 2>/dev/null >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 3: PASS — acronym defined in-diff via parenthetical ----
  RC=$(_run_scenario s3 "$IN_SCOPE_DEFINED_DIFF" "$GLOSSARY_BASIC")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (3) PASS-defined-in-diff: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (3) PASS-defined-in-diff: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s3/stderr.txt" 2>/dev/null >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 4 (Wave D.6 demotion): undefined acronym, no parenthetical,
  # not in glossary -> WARN-shape: exit 0 + warn text on stderr (was BLOCK
  # exit 1 pre-demotion). ----
  RC=$(_run_scenario s4 "$IN_SCOPE_UNDEFINED" "$GLOSSARY_BASIC")
  if [[ "$RC" == "0" ]] && grep -q "verdict=WARN" "$TMPROOT/s4/stderr.txt" 2>/dev/null; then
    echo "self-test (4) WARN-undefined-acronym: PASS (rc=$RC, expected 0; demoted to warn)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (4) WARN-undefined-acronym: FAIL (rc=$RC, expected 0 + verdict=WARN in stderr)" >&2
    cat "$TMPROOT/s4/stderr.txt" 2>/dev/null >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 5: PASS — only stopwords used (URL, JSON, HTTP, API, CSV) ----
  RC=$(_run_scenario s5 "$IN_SCOPE_STOPWORD_ONLY" "$GLOSSARY_BASIC")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (5) PASS-stopwords-not-flagged: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (5) PASS-stopwords-not-flagged: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s5/stderr.txt" 2>/dev/null >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 6: PASS — no glossary present, degrades gracefully ----
  RC=$(_run_scenario s6 "$IN_SCOPE_DEFINED_DIFF" "")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (6) PASS-no-glossary-graceful-degrade: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (6) PASS-no-glossary-graceful-degrade: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s6/stderr.txt" 2>/dev/null >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 7 (Wave D.6 demotion): single-word parenthetical not
  # recognized as definition -> WARN-shape: exit 0 + warn text on stderr
  # (was BLOCK exit 1 pre-demotion). ----
  RC=$(_run_scenario s7 "$IN_SCOPE_DIFF_SINGLE_WORD_PAREN" "$GLOSSARY_BASIC")
  if [[ "$RC" == "0" ]] && grep -q "verdict=WARN" "$TMPROOT/s7/stderr.txt" 2>/dev/null; then
    echo "self-test (7) WARN-single-word-paren-not-definition: PASS (rc=$RC, expected 0; demoted to warn)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (7) WARN-single-word-paren-not-definition: FAIL (rc=$RC, expected 0 + verdict=WARN in stderr)" >&2
    cat "$TMPROOT/s7/stderr.txt" 2>/dev/null >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 7 scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# Main hook logic
# ============================================================

# --- Read tool input (env var OR stdin, supporting both Claude Code shapes) ---
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]] && [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
if [[ -z "$INPUT" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Tool name must be Bash
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Extract command
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null)
if [[ -z "$CMD" ]]; then
  exit 0
fi

# Detect git commit (after stripping leading `cd …` and `&&`-prefixed segments)
IS_GIT_COMMIT=0
TMP_CMD=$(echo "$CMD" | sed -e 's/&&/\n/g' -e 's/;/\n/g')
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  seg="${seg%"${seg##*[![:space:]]}"}"
  [[ -z "$seg" ]] && continue
  if [[ "$seg" =~ ^cd[[:space:]] ]] || [[ "$seg" == "cd" ]]; then
    continue
  fi
  if [[ "$seg" =~ ^git[[:space:]]+commit($|[[:space:]]+) ]]; then
    if [[ ! "$seg" =~ ^git[[:space:]]+commit-(tree|graph) ]]; then
      IS_GIT_COMMIT=1
      break
    fi
  fi
done <<< "$TMP_CMD"

if [[ "$IS_GIT_COMMIT" -eq 0 ]]; then
  exit 0
fi

# Locate repo root
REPO_ROOT=""
if command -v git >/dev/null 2>&1; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi

# Get staged in-scope files
IN_SCOPE_FILES=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" == neural-lace/build-doctrine/*.md ]] || [[ "$f" =~ ^neural-lace/build-doctrine/.+\.md$ ]]; then
    IN_SCOPE_FILES+=("$f")
  fi
done < <(git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR 2>/dev/null)

# If no in-scope files, gate is a no-op
if [[ "${#IN_SCOPE_FILES[@]}" -eq 0 ]]; then
  exit 0
fi

# Resolve glossary path
GLOSSARY=$(_resolve_glossary "$REPO_ROOT")
GLOSSARY_WARN=0
if [[ -z "$GLOSSARY" ]]; then
  GLOSSARY_WARN=1
fi

# Iterate in-scope files, find first undefined acronym
FAIL_FILE=""
FAIL_TERM=""
for file in "${IN_SCOPE_FILES[@]}"; do
  added_content=$(_added_lines "$file" "$REPO_ROOT")
  acronyms=$(_extract_acronyms "$file" "$REPO_ROOT")
  while IFS= read -r term; do
    [[ -z "$term" ]] && continue
    # Skip stopwords
    if _is_stopword "$term"; then
      continue
    fi
    # Check glossary (only if glossary resolved)
    if [[ -n "$GLOSSARY" ]] && _in_glossary "$term" "$GLOSSARY"; then
      continue
    fi
    # Check in-diff parenthetical
    if _in_diff_definition "$term" "$added_content"; then
      continue
    fi
    # Undefined!
    FAIL_FILE="$file"
    FAIL_TERM="$term"
    break 2
  done <<< "$acronyms"
done

if [[ -n "$FAIL_TERM" ]]; then
  GLOSSARY_LINE="<none found at configured paths>"
  [[ -n "$GLOSSARY" ]] && GLOSSARY_LINE="$GLOSSARY"
  WARN_BODY="================================================================
DEFINITION-ON-FIRST-USE GATE — undefined acronym (WARN, not a block)
================================================================

Undefined acronym: '$FAIL_TERM'
Found in:          $FAIL_FILE
Glossary checked:  $GLOSSARY_LINE

Remediation (pick one):
  1. Add an entry to the glossary:
     **$FAIL_TERM** — <one-line definition>.
  2. Define in-context in the same diff via parenthetical:
     $FAIL_TERM (foo bar baz) ...
     (parenthetical must contain at least 2 words within ~30 chars)

Stopwords (universally-understood, never flagged): OK, OR, JSON,
  URL, API, HTTP, CSS, ID, etc. — see Decision 023b for full list.

Rule:     adapters/claude-code/rules/definition-on-first-use.md
Decision: docs/decisions/023-definition-on-first-use-enforcement.md

[definition-first-use] file=$FAIL_FILE term=$FAIL_TERM verdict=WARN
================================================================"
  printf '%s\n' "$WARN_BODY" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "[definition-on-first-use-gate] WARN (demoted from block, Wave D.6): undefined acronym '$FAIL_TERM'
$WARN_BODY" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$ctx}}'
  fi
  command -v ledger_emit >/dev/null 2>&1 && ledger_emit "definition-on-first-use-gate" "warn" "undefined acronym '$FAIL_TERM' in $FAIL_FILE"
  exit 0
fi

# PASS
if [[ "$GLOSSARY_WARN" -eq 1 ]]; then
  echo "[definition-first-use] warning: glossary not found at \$HOME/claude-projects/Build Doctrine/outputs/glossary.md or \${REPO}/build-doctrine/outputs/glossary.md; allowed by graceful degrade" >&2
fi
echo "[definition-first-use] files=${#IN_SCOPE_FILES[@]} verdict=PASS" >&2
exit 0
