#!/bin/bash
# doc-gate.sh — F7 dev-doc gate (warn-mode default), 2026-05-30
#
# DEMOTED to ALWAYS non-blocking warn at NL Overhaul Wave D.6 (§D.0.4 /
# §D.6 item 8, 2026-07-02): this gate already defaulted to warn-mode;
# the remaining `enforce`-mode path (opt-in via DOC_GATE_MODE=enforce)
# that used to `exit 2` (block) now ALSO exits 0 and instead emits a
# hookSpecificOutput.additionalContext warn (the sanctioned channel
# that reaches model context) plus a signal-ledger `warn` event.
# Detection logic is UNCHANGED — only the verdict emission changed.
# manifest.json's `blocking` flag for this unit flips to false in the
# same wave (D.5 template/manifest cutover). DOC_GATE_MODE=enforce is
# now purely cosmetic (changes the message header) — it no longer
# blocks.
#
# Classification: Mechanism (PreToolUse Bash hook on `git commit`)
#
# Purpose: enforces the global convention that every change to
# `src/**/*.ts(x)` is accompanied by a corresponding edit to
# `docs/dev/<path>.md`. Catches the "code shipped, docs forgotten"
# drift at commit time before it propagates across many sessions.
#
# Two modes (controlled by DOC_GATE_MODE env var, default warn):
#   warn    — print a one-paragraph stderr warning naming the
#             code-files-without-docs, then ALLOW the commit (exit 0).
#   enforce — emit JSON {"decision":"block",...} on stdout + stderr
#             remediation, refuse the commit (exit 2).
#
# The default is `warn` for a 2-week soak-in period before flipping
# globally to `enforce`. Flipping the default is a one-line edit at the
# top of this script (DEFAULT_MODE=enforce), not a settings change.
# Per-machine override: export DOC_GATE_MODE=enforce|warn in shell rc.
#
# Per-commit opt-out: include `[skip-docs: <reason>]` in the commit
# message body (via `-m`). The hook extracts the reason, logs it to
# ~/.claude/state/doc-gate-bypass-log.jsonl (one JSON line per bypass),
# and allows the commit. The reason text after the colon is captured
# until the closing `]` and must be ≥ 1 non-whitespace char.
#
# Per-project opt-out: the hook is a silent no-op if `docs/dev/` does
# not exist at the repo root. Projects that don't follow the dev-docs
# convention pay zero cost — adoption is implicit on `mkdir docs/dev`.
#
# Path correspondence (MVP, file-level 1:1 mapping):
#   src/foo/bar.ts        → docs/dev/foo/bar.md
#   src/components/X.tsx  → docs/dev/components/X.md
#   src/lib/util.ts       → docs/dev/lib/util.md
#
# AST-comparison / multi-doc-per-code mapping is a follow-up. The
# bypass marker covers the temporary gap for cases the 1:1 mapping
# doesn't fit.
#
# Exempt code paths (never trigger the gate):
#   - *.test.ts, *.test.tsx, *.spec.ts, *.spec.tsx
#   - *.d.ts (TypeScript declaration files)
#   - **/__tests__/**, **/__mocks__/**, **/test/**, **/tests/**
#   - src/types/**, src/**/types.ts (type-only modules)
#   - Files in pure-delete state (staged `D`) — deleting code doesn't
#     require touching the corresponding doc; the maintainer can clean
#     it up in a follow-up commit if it becomes orphaned.
#
# INVOCATION MODES
#   1. PreToolUse on `git commit …` — reads stdin JSON
#                                     (.tool_name + .tool_input.command)
#   2. Self-test:  doc-gate.sh --self-test
#
# EXIT CODES
#   0 — commit allowed (no code-without-doc; warn mode; bypass marker;
#                       no docs/dev/ convention; not a git commit; etc.)
#   2 — commit blocked (enforce mode, ≥ 1 code file missing its doc,
#                       no bypass marker)
#
# AUDIT LOG (bypass)
#   ~/.claude/state/doc-gate-bypass-log.jsonl
#   {"ts":"...","reason":"...","repo":"...","branch":"...",
#    "head":"...","code_files":[...],"mode":"warn|enforce"}
#
# RELATED
#   - A project-tier user-doc gate (a separate hook that may live in
#     a downstream consumer project, with project-specific routing) is
#     out of scope for this global gate; this hook is the GLOBAL
#     dev-doc-for-source-code gate that ships in the harness layer.
#   - Sibling pattern: decisions-index-gate.sh (commit-time
#     atomicity of two related artifacts) and docs-freshness-gate.sh
#     (structural-change → docs-touched).

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/signal-ledger.sh
source "$SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true

# Hard-coded default mode for the soak-in period. Flip to "enforce"
# after the soak window. Per-session override via DOC_GATE_MODE env var.
DEFAULT_MODE="warn"

# ============================================================
# --self-test handler
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF_TEST_HOOK" ]]; then
    echo "self-test: cannot resolve own path" >&2
    exit 2
  fi

  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t doc-gate)
  if [[ -z "$TMPROOT" ]] || [[ ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  PASSED=0
  FAILED=0

  # Helper: build a fresh repo with docs/dev/ + staged files, invoke
  # the hook with a synthesized PreToolUse JSON. Returns hook's exit
  # code (or 99 on setup failure).
  #
  # Args: $1 = scenario label
  #       $2 = "yes"|"no" — create docs/dev/ directory
  #       $3 = comma-separated staged file paths (created empty + added)
  #       $4 = commit -m message argument (literal)
  #       $5 = DOC_GATE_MODE override ("" for default)
  _run_scenario() {
    local label="$1" want_docsdev="$2" staged_csv="$3" cmsg="$4" mode_override="$5"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo"
    (
      cd "$repo" || exit 99
      git init -q 2>/dev/null || true
      git config core.hooksPath "" 2>/dev/null  # don't fire machine-global harness git hooks in fixtures
      git config user.email "test@example.com" 2>/dev/null
      git config user.name "Test" 2>/dev/null
      git config commit.gpgsign false 2>/dev/null
      # Seed a HEAD so diff-cached has a baseline
      echo "init" > .keep
      git add .keep 2>/dev/null
      git commit -q -m "init" 2>/dev/null

      if [[ "$want_docsdev" == "yes" ]]; then
        mkdir -p docs/dev
        # Keep the dir tracked so it exists for the hook's check
        touch docs/dev/.gitkeep
        git add docs/dev/.gitkeep 2>/dev/null
        git commit -q -m "seed docs/dev" 2>/dev/null
      fi

      IFS=',' read -ra STAGED <<< "$staged_csv"
      for f in "${STAGED[@]}"; do
        [[ -z "$f" ]] && continue
        mkdir -p "$(dirname "$f")" 2>/dev/null
        echo "stub" > "$f"
        git add "$f" 2>/dev/null
      done

      # Build PreToolUse JSON. Escape `"` inside the message.
      local esc_msg
      esc_msg=${cmsg//\\/\\\\}
      esc_msg=${esc_msg//\"/\\\"}
      local input
      input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m \\\"${esc_msg}\\\"\"}}"

      # Invoke the hook with the override env. Redirect stdout (JSON
      # decision) and stderr (warning text) to files for inspection.
      if [[ -n "$mode_override" ]]; then
        printf '%s' "$input" | env DOC_GATE_MODE="$mode_override" bash "$SELF_TEST_HOOK" \
          > stdout.txt 2> stderr.txt
      else
        printf '%s' "$input" | bash "$SELF_TEST_HOOK" \
          > stdout.txt 2> stderr.txt
      fi
      echo $? > rc.txt
    )
    cat "$repo/rc.txt" 2>/dev/null || echo 99
  }

  # Helper: did the scenario's stderr contain a particular substring?
  _stderr_contains() {
    local label="$1" needle="$2"
    grep -F -q "$needle" "$TMPROOT/$label/stderr.txt" 2>/dev/null
  }

  # ---- Scenario s1: PASS — code change + corresponding doc update ----
  # Touches src/foo.ts and docs/dev/foo.md together → silent allow
  RC=$(_run_scenario s1 yes "src/foo.ts,docs/dev/foo.md" "feat: add foo" "")
  if [[ "$RC" == "0" ]] && ! _stderr_contains s1 "DOC GATE"; then
    echo "self-test (s1) code+doc allowed silently: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (s1) code+doc allowed silently: FAIL (rc=$RC)" >&2
    cat "$TMPROOT/s1/stderr.txt" >&2 2>/dev/null
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario s2: PASS-WITH-WARN — code change, no doc update, warn mode ----
  # Default mode is warn → exit 0 but stderr contains DOC GATE warning
  RC=$(_run_scenario s2 yes "src/foo.ts" "feat: add foo without docs" "")
  if [[ "$RC" == "0" ]] && _stderr_contains s2 "DOC GATE" && _stderr_contains s2 "src/foo.ts"; then
    echo "self-test (s2) warn-mode allows with warning: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (s2) warn-mode allows with warning: FAIL (rc=$RC)" >&2
    cat "$TMPROOT/s2/stderr.txt" >&2 2>/dev/null
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario s3 (Wave D.6 demotion): code change, no doc update,
  # enforce mode -> WARN-shape: exit 0 + warn text on stderr (was BLOCK
  # exit 2 pre-demotion; DOC_GATE_MODE=enforce no longer blocks). ----
  RC=$(_run_scenario s3 yes "src/foo.ts" "feat: add foo without docs" "enforce")
  if [[ "$RC" == "0" ]] && _stderr_contains s3 "DOC GATE" && _stderr_contains s3 "src/foo.ts"; then
    echo "self-test (s3) enforce-mode now warns (demoted): PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (s3) enforce-mode now warns (demoted): FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s3/stderr.txt" >&2 2>/dev/null
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario s4: PASS-WITH-LOG — [skip-docs: reason] bypass ----
  # Even in enforce mode, the marker bypasses + logs to JSONL
  HOME_SAVED="$HOME"
  export HOME="$TMPROOT/s4-home"
  mkdir -p "$HOME/.claude/state"
  RC=$(_run_scenario s4 yes "src/foo.ts" "feat: refactor only [skip-docs: trivial rename, no behavior change]" "enforce")
  export HOME="$HOME_SAVED"
  LOG_FILE="$TMPROOT/s4-home/.claude/state/doc-gate-bypass-log.jsonl"
  if [[ "$RC" == "0" ]] \
     && _stderr_contains s4 "skip-docs" \
     && [[ -f "$LOG_FILE" ]] \
     && grep -q "trivial rename" "$LOG_FILE" 2>/dev/null; then
    echo "self-test (s4) [skip-docs:] bypass logged + allowed: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (s4) [skip-docs:] bypass logged + allowed: FAIL (rc=$RC, log=$LOG_FILE)" >&2
    cat "$TMPROOT/s4/stderr.txt" >&2 2>/dev/null
    ls -la "$TMPROOT/s4-home/.claude/state/" 2>&1 >&2 || true
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario s5: PASS — doc-only change (no src touched) ----
  RC=$(_run_scenario s5 yes "docs/dev/foo.md" "docs: update foo notes" "")
  if [[ "$RC" == "0" ]] && ! _stderr_contains s5 "DOC GATE"; then
    echo "self-test (s5) doc-only allowed silently: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (s5) doc-only allowed silently: FAIL (rc=$RC)" >&2
    cat "$TMPROOT/s5/stderr.txt" >&2 2>/dev/null
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario s6: PASS — no docs/dev/ → silent no-op even in enforce ----
  RC=$(_run_scenario s6 no "src/foo.ts" "feat: project without dev-docs convention" "enforce")
  if [[ "$RC" == "0" ]] && ! _stderr_contains s6 "DOC GATE"; then
    echo "self-test (s6) no docs/dev/ silent no-op: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (s6) no docs/dev/ silent no-op: FAIL (rc=$RC)" >&2
    cat "$TMPROOT/s6/stderr.txt" >&2 2>/dev/null
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario s7: PASS — exempt test file (src/foo.test.ts only) ----
  RC=$(_run_scenario s7 yes "src/foo.test.ts" "test: add foo unit test" "enforce")
  if [[ "$RC" == "0" ]] && ! _stderr_contains s7 "DOC GATE"; then
    echo "self-test (s7) test file exempted: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (s7) test file exempted: FAIL (rc=$RC)" >&2
    cat "$TMPROOT/s7/stderr.txt" >&2 2>/dev/null
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario s8: PASS — non-git-commit Bash silently passes ----
  # We invoke the hook directly with a non-commit JSON
  REPO="$TMPROOT/s8"
  mkdir -p "$REPO"
  (cd "$REPO" && git init -q 2>/dev/null && mkdir -p docs/dev)
  STDIN_INPUT='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  set +e
  OUT=$(cd "$REPO" && printf '%s' "$STDIN_INPUT" | bash "$SELF_TEST_HOOK" 2>&1)
  RC=$?
  set -e
  if [[ "$RC" == "0" ]] && [[ -z "$OUT" ]]; then
    echo "self-test (s8) non-commit Bash silent no-op: PASS" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (s8) non-commit Bash silent no-op: FAIL (rc=$RC, out='$OUT')" >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: passed=$PASSED failed=$FAILED" >&2
  if [[ "$FAILED" -gt 0 ]]; then
    echo "self-test: FAIL" >&2
    exit 1
  fi
  echo "self-test: OK" >&2
  exit 0
fi

# ============================================================
# Main hook logic
# ============================================================

# --- Read tool input (env var OR stdin, supporting both shapes) ---
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]] && [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
if [[ -z "$INPUT" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we can't safely parse — pass through (errs toward allow).
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null)
if [[ -z "$CMD" ]]; then
  exit 0
fi

# --- Detect git commit (strip leading `cd …` and `&&`-prefixed blocks) ---
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

# --- Locate repo root ---
REPO_ROOT=""
if command -v git >/dev/null 2>&1; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [[ -z "$REPO_ROOT" ]]; then
  CURRENT="$PWD"
  while [[ -n "$CURRENT" ]] && [[ "$CURRENT" != "/" ]]; do
    if [[ -d "$CURRENT/.git" ]]; then
      REPO_ROOT="$CURRENT"
      break
    fi
    PARENT=$(dirname "$CURRENT")
    [[ "$PARENT" == "$CURRENT" ]] && break
    CURRENT="$PARENT"
  done
fi
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi

# --- Opt-out by convention: no docs/dev/ → silent no-op ---
if [[ ! -d "$REPO_ROOT/docs/dev" ]]; then
  exit 0
fi

# --- Get staged files ---
STAGED_ALL=()
STAGED_DEL=()
if command -v git >/dev/null 2>&1; then
  while IFS=$'\t' read -r status path; do
    [[ -z "$path" ]] && continue
    STAGED_ALL+=("$path")
    if [[ "$status" == "D" ]]; then
      STAGED_DEL+=("$path")
    fi
  done < <(git -C "$REPO_ROOT" diff --cached --name-status --diff-filter=ACMRD 2>/dev/null)
fi

if [[ "${#STAGED_ALL[@]}" -eq 0 ]]; then
  exit 0
fi

# --- Helper: is this path a code file subject to the gate? ---
_is_code_file() {
  local p="$1"
  # Must live under src/ and end .ts or .tsx
  case "$p" in
    src/*.ts|src/*.tsx|src/**/*.ts|src/**/*.tsx) : ;;
    src/*) : ;;
    *) return 1 ;;
  esac
  case "$p" in
    src/*.ts|src/*.tsx) : ;;
    src/*/*) : ;;
    *) return 1 ;;
  esac
  case "$p" in
    *.test.ts|*.test.tsx) return 1 ;;
    *.spec.ts|*.spec.tsx) return 1 ;;
    *.d.ts) return 1 ;;
    */__tests__/*) return 1 ;;
    */__mocks__/*) return 1 ;;
    src/test/*|src/tests/*) return 1 ;;
    */test/*|*/tests/*) return 1 ;;
    src/types/*) return 1 ;;
    */types.ts) return 1 ;;
  esac
  case "$p" in
    *.ts|*.tsx) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Helper: derive expected doc path from a code path ---
# src/foo/bar.ts → docs/dev/foo/bar.md
# src/components/X.tsx → docs/dev/components/X.md
_doc_path_for() {
  local code="$1"
  local rel="${code#src/}"
  # Strip extension
  rel="${rel%.tsx}"
  rel="${rel%.ts}"
  printf 'docs/dev/%s.md' "$rel"
}

# --- Helper: is path in STAGED_DEL? ---
_is_pure_delete() {
  local p="$1" d
  for d in "${STAGED_DEL[@]:-}"; do
    [[ "$d" == "$p" ]] && return 0
  done
  return 1
}

# --- Helper: is path in STAGED_ALL? ---
_is_staged() {
  local p="$1" s
  for s in "${STAGED_ALL[@]:-}"; do
    [[ "$s" == "$p" ]] && return 0
  done
  return 1
}

# --- Collect code-without-doc list ---
MISSING=()
for f in "${STAGED_ALL[@]}"; do
  if _is_code_file "$f"; then
    # Exempt pure deletions
    if _is_pure_delete "$f"; then
      continue
    fi
    doc=$(_doc_path_for "$f")
    if ! _is_staged "$doc"; then
      MISSING+=("$f")
    fi
  fi
done

if [[ "${#MISSING[@]}" -eq 0 ]]; then
  # No code-without-doc — silent allow
  exit 0
fi

# --- Resolve effective mode ---
MODE="${DOC_GATE_MODE:-$DEFAULT_MODE}"
case "$MODE" in
  warn|enforce) : ;;
  *) MODE="$DEFAULT_MODE" ;;
esac

# --- Check for [skip-docs: reason] in commit command ---
# Search the raw command for the marker; capture reason between ":" and "]"
BYPASS_REASON=""
if [[ "$CMD" =~ \[skip-docs:[[:space:]]*([^\]]+)\] ]]; then
  BYPASS_REASON="${BASH_REMATCH[1]}"
  # Trim trailing whitespace
  BYPASS_REASON="${BYPASS_REASON%"${BYPASS_REASON##*[![:space:]]}"}"
fi

if [[ -n "$BYPASS_REASON" ]]; then
  # Log to JSONL and allow
  LOG_DIR="$HOME/.claude/state"
  LOG_FILE="$LOG_DIR/doc-gate-bypass-log.jsonl"
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  HEAD_SHA=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  # Build files JSON array
  FILES_JSON="["
  first=1
  for f in "${MISSING[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      FILES_JSON+=","
    fi
    # Escape quotes in path (defensive — git paths shouldn't contain ")
    esc=${f//\"/\\\"}
    FILES_JSON+="\"$esc\""
  done
  FILES_JSON+="]"
  # Escape quotes/backslashes in reason
  esc_reason=${BYPASS_REASON//\\/\\\\}
  esc_reason=${esc_reason//\"/\\\"}
  esc_repo=${REPO_ROOT//\\/\\\\}
  esc_repo=${esc_repo//\"/\\\"}
  printf '{"ts":"%s","reason":"%s","repo":"%s","branch":"%s","head":"%s","code_files":%s,"mode":"%s"}\n' \
    "$TS" "$esc_reason" "$esc_repo" "$BRANCH" "$HEAD_SHA" "$FILES_JSON" "$MODE" \
    >> "$LOG_FILE" 2>/dev/null || true

  echo "[doc-gate] [skip-docs: $BYPASS_REASON] — bypass logged to $LOG_FILE" >&2
  echo "[doc-gate] ${#MISSING[@]} code file(s) committed without corresponding docs/dev/*.md update:" >&2
  for f in "${MISSING[@]}"; do
    echo "  • $f → expected $(_doc_path_for "$f")" >&2
  done
  exit 0
fi

# --- Emit warning (always; Wave D.6 — enforce mode no longer blocks) ---
WARN_BODY=$(
  echo "================================================================"
  echo "DOC GATE — warning (commit allowed; enforce mode no longer blocks post-Wave-D.6)"
  echo "================================================================"
  echo ""
  echo "Code files staged without a corresponding docs/dev/*.md update:"
  for f in "${MISSING[@]}"; do
    echo "  • $f  →  expected: $(_doc_path_for "$f")"
  done
  echo ""
  echo "Convention: every change to \`src/**/*.ts(x)\` should be accompanied"
  echo "by an edit to the corresponding \`docs/dev/<path>.md\` developer note."
  echo "Test/spec/declaration/types files are exempt; pure-delete commits are exempt."
  echo ""
  echo "To proceed:"
  echo "  1. UPDATE THE DOC (preferred) — edit the expected docs/dev/*.md"
  echo "     file alongside the code change and re-stage."
  echo "  2. BYPASS THIS COMMIT — add \`[skip-docs: <one-line reason>]\` to"
  echo "     your commit message body (via \`-m\`). The bypass is logged to"
  echo "     ~/.claude/state/doc-gate-bypass-log.jsonl for audit."
  echo "  3. OPT OUT THIS PROJECT — \`docs/dev/\` is the opt-in marker. If"
  echo "     your project doesn't follow this convention, remove the"
  echo "     directory and the gate falls silent."
  echo ""
  echo "Mode: $MODE (cosmetic only post-Wave-D.6 — neither warn nor enforce"
  echo "      blocks; override per-session via the DOC_GATE_MODE env var)."
  echo ""
  echo "================================================================"
)
printf '%s\n' "$WARN_BODY" >&2
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "[doc-gate] WARN (demoted from block, Wave D.6): ${#MISSING[@]} code file(s) missing docs/dev update
$WARN_BODY" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$ctx}}'
fi
command -v ledger_emit >/dev/null 2>&1 && ledger_emit "doc-gate" "warn" "${#MISSING[@]} code file(s) missing docs/dev update"

exit 0
