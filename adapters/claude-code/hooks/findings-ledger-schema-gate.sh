#!/bin/bash
# findings-ledger-schema-gate.sh — Phase 1d-C-3 (C9), 2026-05-04
#
# PreToolUse hook (Bash matcher) that blocks `git commit` when the commit
# stages docs/findings.md and any new/modified entry violates the locked
# six-field schema from Decision 019.
#
# Rule (mechanism, Build Doctrine §6 C9 / §9 Q5-A):
#   Every entry in docs/findings.md must have all six required fields:
#     - ID heading: ### <PROJECT-PREFIX>-FINDING-<NNN> — <title>
#     - Severity:   info | warn | error | severe
#     - Scope:      unit | spec | canon | cross-repo
#     - Source:     <any non-empty string>
#     - Location:   <any non-empty string>
#     - Status:     open | in-progress | dispositioned-act |
#                   dispositioned-defer | dispositioned-accept | closed
#     - Description: <any non-empty content; can span multiple lines>
#   Plus: each ID must be unique across the entire docs/findings.md file.
#
# Trigger:
#   PreToolUse on tool_name == "Bash". Detects `git commit` (after stripping
#   leading `cd …` and `&&`-prefixed segments). Pass-through on non-Bash
#   and non-commit Bash commands.
#
# Logic:
#   1. Detect git commit. If not, allow.
#   2. Locate repo root. If no repo, allow.
#   3. Get staged files. If docs/findings.md is not staged, allow (no-op).
#   4. Read the staged content of docs/findings.md (after the commit would
#      land — i.e., the version that exists on disk + index).
#   5. Parse all entries (`### <ID> — <title>` headings) and their bodies.
#   6. For each entry: validate the six fields. Validate ID pattern.
#      Validate enum values for Severity/Scope/Status.
#   7. Validate uniqueness of IDs within the file.
#   8. On any failure → BLOCK with stderr message naming the entry + field.
#
# Exit codes:
#   0 — allow (commit proceeds; no findings.md changes OR all entries valid)
#   1 — block (stderr explains why; JSON {decision: block} on stdout)
#   2 — parse error (passes through to allow; we don't lock up the session)

set -u

# ============================================================
# Helper: validate a single entry
# Args: $1 = entry ID, $2 = entry body (raw, including the heading line)
# Returns 0 if valid, 1 if invalid.
# Sets _ENTRY_FAIL_REASON on failure.
# ============================================================
_ENTRY_FAIL_REASON=""
_validate_entry() {
  local id="$1"
  local body="$2"

  # Validate ID pattern: <PREFIX>-FINDING-<NNN>
  # Prefix is uppercase letters/digits, FINDING is literal, NNN is digits.
  if ! [[ "$id" =~ ^[A-Z][A-Z0-9]*-FINDING-[0-9]+$ ]]; then
    _ENTRY_FAIL_REASON="invalid ID pattern '$id' (expected <PROJECT-PREFIX>-FINDING-<NNN>, e.g., NL-FINDING-001)"
    return 1
  fi

  # Required fields. Each must be present as `- **<Field>:** <value>` on its own line.
  # Severity, Scope, Status are enums; Source, Location, Description need only be non-empty.
  local severity scope source location status description

  severity=$(printf '%s' "$body" | awk -F'\\*\\*Severity:\\*\\*' '
    /\*\*Severity:\*\*/ { val=$2; sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val); print val; exit }
  ')
  scope=$(printf '%s' "$body" | awk -F'\\*\\*Scope:\\*\\*' '
    /\*\*Scope:\*\*/ { val=$2; sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val); print val; exit }
  ')
  source=$(printf '%s' "$body" | awk -F'\\*\\*Source:\\*\\*' '
    /\*\*Source:\*\*/ { val=$2; sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val); print val; exit }
  ')
  location=$(printf '%s' "$body" | awk -F'\\*\\*Location:\\*\\*' '
    /\*\*Location:\*\*/ { val=$2; sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val); print val; exit }
  ')
  status=$(printf '%s' "$body" | awk -F'\\*\\*Status:\\*\\*' '
    /\*\*Status:\*\*/ { val=$2; sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val); print val; exit }
  ')
  # Description: body content after `- **Description:**` until next `### ` heading or EOF.
  # We accept either a single-line value OR multi-line content.
  description=$(printf '%s' "$body" | awk '
    /\*\*Description:\*\*/ {
      sub(/^.*\*\*Description:\*\*[[:space:]]*/, "")
      print
      in_desc = 1
      next
    }
    in_desc {
      if (/^### /) exit
      print
    }
  ')

  # Field-presence checks
  if [[ -z "$severity" ]]; then
    _ENTRY_FAIL_REASON="missing required field 'Severity' (expected: '- **Severity:** <info|warn|error|severe>')"
    return 1
  fi
  if [[ -z "$scope" ]]; then
    _ENTRY_FAIL_REASON="missing required field 'Scope' (expected: '- **Scope:** <unit|spec|canon|cross-repo>')"
    return 1
  fi
  if [[ -z "$source" ]]; then
    _ENTRY_FAIL_REASON="missing required field 'Source'"
    return 1
  fi
  if [[ -z "$location" ]]; then
    _ENTRY_FAIL_REASON="missing required field 'Location'"
    return 1
  fi
  if [[ -z "$status" ]]; then
    _ENTRY_FAIL_REASON="missing required field 'Status' (expected: '- **Status:** <open|in-progress|dispositioned-act|dispositioned-defer|dispositioned-accept|closed>')"
    return 1
  fi
  # Description must have at least 1 non-whitespace char
  local desc_nonws
  desc_nonws=$(printf '%s' "$description" | tr -d '[:space:]' | wc -c | tr -cd '[:digit:]')
  desc_nonws=${desc_nonws:-0}
  if [[ "$desc_nonws" -lt 1 ]]; then
    _ENTRY_FAIL_REASON="missing required field 'Description' (must be non-empty body content)"
    return 1
  fi

  # Enum-value checks (case-insensitive accepted; normalize to lowercase for compare)
  local sev_lc scope_lc status_lc
  sev_lc=$(printf '%s' "$severity" | tr '[:upper:]' '[:lower:]')
  scope_lc=$(printf '%s' "$scope" | tr '[:upper:]' '[:lower:]')
  status_lc=$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')

  case "$sev_lc" in
    info|warn|error|severe) ;;
    *)
      _ENTRY_FAIL_REASON="invalid Severity '$severity' (valid: info, warn, error, severe)"
      return 1
      ;;
  esac
  case "$scope_lc" in
    unit|spec|canon|cross-repo) ;;
    *)
      _ENTRY_FAIL_REASON="invalid Scope '$scope' (valid: unit, spec, canon, cross-repo)"
      return 1
      ;;
  esac
  case "$status_lc" in
    open|in-progress|dispositioned-act|dispositioned-defer|dispositioned-accept|closed) ;;
    *)
      _ENTRY_FAIL_REASON="invalid Status '$status' (valid: open, in-progress, dispositioned-act, dispositioned-defer, dispositioned-accept, closed)"
      return 1
      ;;
  esac

  return 0
}

# ============================================================
# Helper: parse all entries from a findings.md file. Returns via
# globals: _ENTRY_IDS (array), _ENTRY_BODIES (newline-joined and
# delimited via a sentinel; we re-extract per-entry for validation).
# Strategy: walk the file; each `### <id> — <title>` heading starts
# a new entry; entry body is lines until next `### ` heading or EOF.
#
# Sets _ALL_ENTRIES_OK=1 if every entry validates, 0 otherwise.
# Sets _FIRST_FAIL_ID and _FIRST_FAIL_REASON on first failure.
# ============================================================
_ALL_ENTRIES_OK=1
_FIRST_FAIL_ID=""
_FIRST_FAIL_REASON=""
_VALIDATE_FILE() {
  local file="$1"
  _ALL_ENTRIES_OK=1
  _FIRST_FAIL_ID=""
  _FIRST_FAIL_REASON=""

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  # Use awk to enumerate entries: each starts with `### <ID> — <title>`
  # We collect IDs first to check uniqueness, then validate each body.
  local ids_file bodies_dir
  ids_file=$(mktemp)
  bodies_dir=$(mktemp -d)
  # Cleanup trap is handled by caller; this fn is called once per hook fire.

  awk -v bd="$bodies_dir" -v idf="$ids_file" '
    /^### / {
      # Close previous body
      if (current_id != "") {
        close(bd "/" current_id ".body")
      }
      # Extract ID: heading is "### <ID> — <title>" or "### <ID> -- <title>" or "### <ID>"
      line = $0
      sub(/^### [[:space:]]*/, "", line)
      # Take first whitespace-bounded token as ID
      n = split(line, parts, /[[:space:]]/)
      id = parts[1]
      # Strip trailing punctuation chars from ID
      gsub(/[,;:]$/, "", id)
      current_id = id
      print id >> idf
      print $0 > (bd "/" id ".body")
      next
    }
    {
      if (current_id != "") {
        print $0 >> (bd "/" current_id ".body")
      }
    }
  ' "$file" 2>/dev/null

  # Check for duplicate IDs
  local dup
  dup=$(sort "$ids_file" | uniq -d | head -1)
  if [[ -n "$dup" ]]; then
    _ALL_ENTRIES_OK=0
    _FIRST_FAIL_ID="$dup"
    _FIRST_FAIL_REASON="duplicate ID '$dup' (each ID must appear exactly once in docs/findings.md)"
    rm -f "$ids_file"
    rm -rf "$bodies_dir"
    return 1
  fi

  # Validate each entry
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local body_file="$bodies_dir/$id.body"
    [[ -f "$body_file" ]] || continue
    local body
    body=$(cat "$body_file")
    if ! _validate_entry "$id" "$body"; then
      _ALL_ENTRIES_OK=0
      _FIRST_FAIL_ID="$id"
      _FIRST_FAIL_REASON="$_ENTRY_FAIL_REASON"
      rm -f "$ids_file"
      rm -rf "$bodies_dir"
      return 1
    fi
  done < "$ids_file"

  # Detect orphaned field bullets — lines that look like finding fields
  # (`- **Severity:**` etc.) but appear OUTSIDE any `### ` heading. This
  # catches the case where a contributor pasted field bullets without
  # adding the required heading.
  local orphan_count
  orphan_count=$(awk '
    /^### / { in_entry = 1; next }
    /^## / && !/^### / { in_entry = 0 }
    !in_entry && /^[[:space:]]*-[[:space:]]+\*\*(Severity|Scope|Source|Location|Status|Description):\*\*/ {
      orphans++
    }
    END { print orphans + 0 }
  ' "$file" 2>/dev/null)
  orphan_count=${orphan_count:-0}
  if [[ "$orphan_count" -gt 0 ]]; then
    _ALL_ENTRIES_OK=0
    _FIRST_FAIL_ID="<no heading>"
    _FIRST_FAIL_REASON="found $orphan_count orphaned field bullet(s) (Severity/Scope/Source/Location/Status/Description) outside any '### <ID> — <title>' heading; every entry MUST start with a heading line"
    rm -f "$ids_file"
    rm -rf "$bodies_dir"
    return 1
  fi

  rm -f "$ids_file"
  rm -rf "$bodies_dir"
  return 0
}

# ============================================================
# --self-test handler (six scenarios)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF_TEST_HOOK" ]]; then
    echo "self-test: cannot resolve own path" >&2
    exit 2
  fi

  PASSED=0
  FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t findings-schema)
  if [[ -z "$TMPROOT" ]] || [[ ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  # Helper: build a synthetic repo with optional findings.md content +
  # optional staged files, then invoke the hook against synthesized
  # PreToolUse Bash JSON for git commit. Returns hook's exit code.
  #
  # Args: $1 = scenario label
  #       $2 = findings.md content (empty = don't create the file)
  #       $3 = "1" to stage findings.md, "0" to leave unstaged
  #       $4 = optional extra staged file name (relative path)
  _run_scenario() {
    local label="$1"
    local findings_body="$2"
    local stage_findings="$3"
    local extra_staged="${4:-}"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo/docs"
    (
      cd "$repo" || exit 99
      git init -q 2>/dev/null || true
      git config user.email "test@example.com" 2>/dev/null
      git config user.name "Test" 2>/dev/null
      git config commit.gpgsign false 2>/dev/null

      # Make an initial empty commit so HEAD exists
      echo "init" > .gitkeep
      git add .gitkeep 2>/dev/null
      git commit -q -m "init repo" 2>/dev/null

      if [[ -n "$findings_body" ]]; then
        printf '%s' "$findings_body" > "docs/findings.md"
      fi

      if [[ "$stage_findings" == "1" ]] && [[ -f "docs/findings.md" ]]; then
        git add docs/findings.md 2>/dev/null
      fi

      if [[ -n "$extra_staged" ]]; then
        mkdir -p "$(dirname "$extra_staged")" 2>/dev/null
        echo "stub" > "$extra_staged"
        git add "$extra_staged" 2>/dev/null
      fi

      local input='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}'
      printf '%s' "$input" | bash "$SELF_TEST_HOOK" >stdout.txt 2>stderr.txt
      echo $? > rc.txt
    )
    cat "$repo/rc.txt" 2>/dev/null || echo 99
  }

  # ---- Test fixtures ----

  FINDINGS_VALID='# Findings ledger

## Schema specification

Six required fields per entry.

## Entries

### NL-FINDING-001 — example valid entry

- **Severity:** warn
- **Scope:** unit
- **Source:** orchestrator (manual)
- **Location:** adapters/claude-code/hooks/example.sh:line-42
- **Status:** open
- **Description:** This is the descriptive body of the entry. It explains what was observed and why.
'

  FINDINGS_MISSING_HEADING='# Findings ledger

## Entries

- **Severity:** warn
- **Scope:** unit
- **Source:** orchestrator
- **Location:** somewhere
- **Status:** open
- **Description:** body lacking the ### heading entirely
'

  FINDINGS_INVALID_SEVERITY='# Findings ledger

## Entries

### NL-FINDING-002 — bad severity

- **Severity:** critical
- **Scope:** unit
- **Source:** orchestrator
- **Location:** somewhere:1
- **Status:** open
- **Description:** Severity is "critical" which is not in the enum.
'

  FINDINGS_INVALID_STATUS='# Findings ledger

## Entries

### NL-FINDING-003 — bad status

- **Severity:** info
- **Scope:** unit
- **Source:** orchestrator
- **Location:** somewhere:1
- **Status:** pending
- **Description:** Status "pending" is not in the locked enum.
'

  FINDINGS_DUPLICATE='# Findings ledger

## Entries

### NL-FINDING-001 — first

- **Severity:** info
- **Scope:** unit
- **Source:** orchestrator
- **Location:** somewhere:1
- **Status:** open
- **Description:** First entry with id 001.

### NL-FINDING-001 — duplicate id

- **Severity:** info
- **Scope:** unit
- **Source:** orchestrator
- **Location:** elsewhere:2
- **Status:** open
- **Description:** Second entry reuses the same id; should fail.
'

  # ---- Scenario 1: PASS-valid-entry ----
  RC=$(_run_scenario s1 "$FINDINGS_VALID" "1" "")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (1) PASS-valid-entry: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (1) PASS-valid-entry: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s1/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 2: PASS-no-findings-changes (commit doesn't touch findings.md) ----
  RC=$(_run_scenario s2 "" "0" "src/some-file.ts")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (2) PASS-no-findings-changes: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (2) PASS-no-findings-changes: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s2/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 3: FAIL-missing-id (heading absent) ----
  RC=$(_run_scenario s3 "$FINDINGS_MISSING_HEADING" "1" "")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (3) FAIL-missing-id: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (3) FAIL-missing-id: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s3/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 4: FAIL-invalid-severity ----
  RC=$(_run_scenario s4 "$FINDINGS_INVALID_SEVERITY" "1" "")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (4) FAIL-invalid-severity: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (4) FAIL-invalid-severity: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s4/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 5: FAIL-invalid-status ----
  RC=$(_run_scenario s5 "$FINDINGS_INVALID_STATUS" "1" "")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (5) FAIL-invalid-status: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (5) FAIL-invalid-status: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s5/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 6: FAIL-duplicate-id ----
  RC=$(_run_scenario s6 "$FINDINGS_DUPLICATE" "1" "")
  if [[ "$RC" == "1" ]]; then
    echo "self-test (6) FAIL-duplicate-id: PASS (rc=$RC, expected 1; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (6) FAIL-duplicate-id: FAIL (rc=$RC, expected 1)" >&2
    cat "$TMPROOT/s6/stderr.txt" >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 6 scenarios)" >&2
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

# Get staged files
STAGED_FINDINGS=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" == "docs/findings.md" ]]; then
    STAGED_FINDINGS=1
    break
  fi
done < <(git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMRD 2>/dev/null)

# If docs/findings.md isn't staged, gate is a no-op
if [[ "$STAGED_FINDINGS" -eq 0 ]]; then
  exit 0
fi

FINDINGS_FILE="$REPO_ROOT/docs/findings.md"
if [[ ! -f "$FINDINGS_FILE" ]]; then
  # Staged but missing on disk — the staged content lives in the index.
  # Extract it via `git show :docs/findings.md` to a temp file.
  TMP_FINDINGS=$(mktemp)
  trap 'rm -f "$TMP_FINDINGS"' EXIT
  if ! git -C "$REPO_ROOT" show ":docs/findings.md" > "$TMP_FINDINGS" 2>/dev/null; then
    # Cannot read the staged content; pass through (errs toward allow)
    exit 0
  fi
  FINDINGS_FILE="$TMP_FINDINGS"
fi

# Validate
if ! _VALIDATE_FILE "$FINDINGS_FILE"; then
  ENTRY_COUNT=$(grep -c '^### ' "$FINDINGS_FILE" 2>/dev/null | tr -cd '[:digit:]')
  ENTRY_COUNT=${ENTRY_COUNT:-0}
  {
    echo "================================================================"
    echo "FINDINGS-LEDGER SCHEMA GATE — COMMIT BLOCKED"
    echo "================================================================"
    echo ""
    echo "docs/findings.md is staged but contains a malformed entry."
    echo ""
    if [[ -n "$_FIRST_FAIL_ID" ]]; then
      echo "Failing entry: $_FIRST_FAIL_ID"
    fi
    echo "Reason:        $_FIRST_FAIL_REASON"
    echo ""
    echo "Required schema (locked per Decision 019, 6 fields):"
    echo "  - ID heading: ### <PROJECT-PREFIX>-FINDING-<NNN> — <title>"
    echo "  - **Severity:** info | warn | error | severe"
    echo "  - **Scope:**    unit | spec | canon | cross-repo"
    echo "  - **Source:**   <which gate / agent / role>"
    echo "  - **Location:** <file:line, artifact path, or n/a>"
    echo "  - **Status:**   open | in-progress | dispositioned-act |"
    echo "                  dispositioned-defer | dispositioned-accept | closed"
    echo "  - **Description:** <non-empty body content>"
    echo ""
    echo "Template: adapters/claude-code/templates/findings-template.md"
    echo "Rule:     adapters/claude-code/rules/findings-ledger.md"
    echo ""
    echo "[findings-schema] entries=$ENTRY_COUNT verdict=FAIL field='$_FIRST_FAIL_REASON' entry='$_FIRST_FAIL_ID'"
    echo "================================================================"
  } >&2

  cat <<'JSON'
{"decision": "block", "reason": "Findings-ledger schema gate: docs/findings.md contains a malformed entry. See stderr for the failing entry ID and missing/invalid field."}
JSON
  exit 1
fi

# PASS
ENTRY_COUNT=$(grep -c '^### ' "$FINDINGS_FILE" 2>/dev/null || echo 0)
ENTRY_COUNT=${ENTRY_COUNT:-0}
echo "[findings-schema] entries=$ENTRY_COUNT verdict=PASS" >&2
exit 0
