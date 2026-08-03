# concurrent-ownership-gate-body.sh — the full mechanism (setup helpers,
# --self-test, main hook logic) for concurrent-ownership-gate.sh, SOURCED
# (never executed directly) by that thin entry file. Full spec/header
# (trigger, BLOCKS-when, OWNERSHIP, WAIVER, KNOWN LIMITS, env knobs, exit
# codes) lives in concurrent-ownership-gate.sh's own header — read that
# first. This split exists so a Bash/PowerShell/Edit/Write/MultiEdit event
# this gate does not even apply to (the common case — most tool calls touch
# neither docs/plans/ nor a branch/worktree operation) never pays the cost
# of parsing this file at all: the entry's relevance pre-filter decides
# BEFORE sourcing this body (Gate Philosophy Law, R3.4, harness-execution-
# redesign-2026-08 Task 2).
#
# _COG_SELF_DIR here resolves to THIS file's directory (adapters/claude-code/
# hooks/), which is byte-identical to the entry's directory (both live in
# hooks/), so lib/* sourcing below is unaffected by the split.
_COG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/waiver-purpose-clause.sh
source "$_COG_SELF_DIR/lib/waiver-purpose-clause.sh" 2>/dev/null || true
# shellcheck source=lib/signal-ledger.sh
source "$_COG_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true
# shellcheck source=lib/gate-contract-lib.sh
source "$_COG_SELF_DIR/lib/gate-contract-lib.sh" 2>/dev/null || true
# GC_MODE: computed once from the entry's frozen argv[1] (_COG_ARGV1, set by
# the entry before sourcing this body — NOT bash's own "$1", which inside a
# later-defined function would resolve to that function's own first
# argument, not the script's). See _block() below and gc_mode's header.
GC_MODE="$(gc_mode "${_COG_ARGV1:-}" 2>/dev/null || echo enforce)"

COG_CLAIM_FRESH_SECONDS="${COG_CLAIM_FRESH_SECONDS:-7200}"
if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
  # Sandbox: never read the operator's real claims during a self-test.
  COG_CLAIMS_DIR="${COG_CLAIMS_DIR:-${TMPDIR:-/tmp}/cog-selftest-claims-$$}"
else
  COG_CLAIMS_DIR="${COG_CLAIMS_DIR:-$HOME/.claude/state/active-session-broadcast/claims}"
fi

# ============================================================
# Path / string helpers
# ============================================================

# Normalize a path for equality comparison across Git Bash (/c/Users/...),
# Windows drive-letter (C:/Users/...), and backslash forms. Lowercased.
_norm_path() {
  local p="$1"
  p="${p//\\//}"
  if [[ "$p" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    local d rest
    d=$(printf '%s' "${BASH_REMATCH[1]}" | tr 'A-Z' 'a-z')
    rest="${BASH_REMATCH[2]}"
    p="/${d}${rest}"
  fi
  # squeeze duplicate slashes (JSON-escaped backslash paths decode to //)
  while [[ "$p" == *"//"* ]]; do p="${p//\/\///}"; done
  if [[ -d "$p" ]]; then
    p=$(cd "$p" 2>/dev/null && pwd -P 2>/dev/null) || true
  fi
  printf '%s' "$p" | tr 'A-Z' 'a-z'
}

# Expand a leading ~ / ~/ to $HOME.
_expand_tilde() {
  local p="$1"
  case "$p" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${p#\~/}" ;;
    *) printf '%s' "$p" ;;
  esac
}

_is_abs_path_str() {
  case "$1" in
    /*) return 0 ;;
    [A-Za-z]:/*|[A-Za-z]:\\*) return 0 ;;
    *) return 1 ;;
  esac
}

# Tokenize a command segment respecting single/double quotes.
# Populates global array SEG_TOKENS. (Pattern from scope-enforcement-gate.sh.)
_tokenize_segment() {
  local s="$1" i ch n cur="" in_dq=0 in_sq=0 have=0
  SEG_TOKENS=()
  n=${#s}
  for ((i=0; i<n; i++)); do
    ch="${s:i:1}"
    if [[ $in_sq -eq 1 ]]; then
      if [[ "$ch" == "'" ]]; then in_sq=0; else cur+="$ch"; fi
      continue
    fi
    if [[ $in_dq -eq 1 ]]; then
      if [[ "$ch" == '"' ]]; then in_dq=0; else cur+="$ch"; fi
      continue
    fi
    case "$ch" in
      "'") in_sq=1; have=1 ;;
      '"') in_dq=1; have=1 ;;
      ' '|$'\t')
        if [[ -n "$cur" ]] || [[ $have -eq 1 ]]; then
          SEG_TOKENS+=("$cur"); cur=""; have=0
        fi
        ;;
      *) cur+="$ch"; have=1 ;;
    esac
  done
  if [[ -n "$cur" ]] || [[ $have -eq 1 ]]; then
    SEG_TOKENS+=("$cur")
  fi
}

# Compose a directory path: absolute $3 wins; else resolve against $1 (the
# accumulated target) or $2 (the base cwd).
_compose_dir() {
  local cur="$1" base="$2" p="$3"
  p=$(_expand_tilde "$p")
  if _is_abs_path_str "$p"; then
    printf '%s' "$p"
  elif [[ -n "$cur" ]]; then
    printf '%s/%s' "$cur" "$p"
  elif [[ -n "$base" ]]; then
    printf '%s/%s' "$base" "$p"
  else
    printf '%s' "$p"
  fi
}

# Parse a `cd <path>` / `Set-Location <path>` segment; echo the resolved target.
_parse_cd_target() {
  local seg="$1" base="$2"
  _tokenize_segment "$seg"
  local n=${#SEG_TOKENS[@]}
  if [[ $n -lt 2 ]]; then
    printf '%s' "$HOME"
    return
  fi
  local p="${SEG_TOKENS[1]}"
  if [[ "$p" == -* ]] && [[ $n -ge 3 ]]; then
    p="${SEG_TOKENS[2]}"
  fi
  p=$(_expand_tilde "$p")
  if _is_abs_path_str "$p"; then
    printf '%s' "$p"
  elif [[ -n "$base" ]]; then
    printf '%s/%s' "$base" "$p"
  else
    printf '%s' "$p"
  fi
}

# Analyze a `git …` segment generically. Sets globals:
#   G_SUB       — the git subcommand token ("" if none found)
#   G_ARGS      — array of tokens after the subcommand
#   G_C_TARGET  — composed `-C` target dir ("" when absent)
_analyze_git_generic() {
  local seg="$1" base="$2"
  G_SUB=""
  G_ARGS=()
  G_C_TARGET=""
  _tokenize_segment "$seg"
  local n=${#SEG_TOKENS[@]} i=1 tok
  [[ $n -ge 2 ]] || return 0
  [[ "${SEG_TOKENS[0]}" == "git" ]] || return 0
  while [[ $i -lt $n ]]; do
    tok="${SEG_TOKENS[$i]}"
    case "$tok" in
      -C)
        i=$((i+1))
        [[ $i -lt $n ]] && G_C_TARGET=$(_compose_dir "$G_C_TARGET" "$base" "${SEG_TOKENS[$i]}")
        ;;
      -C?*)
        G_C_TARGET=$(_compose_dir "$G_C_TARGET" "$base" "${tok:2}")
        ;;
      --git-dir|--work-tree|--namespace|-c)
        i=$((i+1))
        ;;
      -*)
        :
        ;;
      *)
        G_SUB="$tok"
        i=$((i+1))
        break
        ;;
    esac
    i=$((i+1))
  done
  while [[ $i -lt $n ]]; do
    G_ARGS+=("${SEG_TOKENS[$i]}")
    i=$((i+1))
  done
  return 0
}

# ============================================================
# Ownership helpers
# ============================================================

# Strip a trailing -YYYY-MM-DD date suffix from a plan slug.
_slug_core() {
  local s="$1"
  printf '%s' "$s" | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}$//'
}

# Repo identity of $1 (a repo root) for claim scoping — MUST mirror
# broadcast-active-session.sh's _repo_identity: the origin push URL when one
# exists (stable across worktrees/clones of the same repo), else the absolute
# git common dir (shared by all linked worktrees of one repo).
_repo_identity() {
  local url
  url=$(git -C "$1" remote get-url --push origin 2>/dev/null || echo "")
  if [[ -n "$url" ]]; then
    printf '%s' "$url"
    return 0
  fi
  git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo ""
}

# Load OTHER worktrees of $REPO_ROOT (excluding $REPO_ROOT itself).
# Populates parallel arrays OTHER_WT_PATHS / OTHER_WT_BRANCHES.
_load_other_worktrees() {
  OTHER_WT_PATHS=()
  OTHER_WT_BRANCHES=()
  local root_norm cur_path="" line
  root_norm=$(_norm_path "$REPO_ROOT")
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur_path="${line#worktree }" ;;
      "branch refs/heads/"*)
        local br="${line#branch refs/heads/}"
        if [[ -n "$cur_path" ]] && [[ "$(_norm_path "$cur_path")" != "$root_norm" ]]; then
          OTHER_WT_PATHS+=("$cur_path")
          OTHER_WT_BRANCHES+=("$br")
        fi
        ;;
      "") cur_path="" ;;
    esac
  done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null)
}

# Load fresh claims from OTHER sessions (claim worktree != $REPO_ROOT),
# REPO-scoped: the claims dir is machine-global, so claims whose "repo"
# identity differs from $REPO_ROOT's are another repo's ownership state and
# are SKIPPED — a claim on branch X of repo A must never block repo B.
# Populates CLAIM_BRANCHES / CLAIM_WORKTREES.
_load_fresh_claims() {
  CLAIM_BRANCHES=()
  CLAIM_WORKTREES=()
  [[ -d "$COG_CLAIMS_DIR" ]] || return 0
  local root_norm fresh_min f br wt rid cur_repo_id
  root_norm=$(_norm_path "$REPO_ROOT")
  cur_repo_id=$(_repo_identity "$REPO_ROOT")
  # FRESHNESS WINDOW via `find -mmin` — NOT a `date -d`-built cutoff,
  # which is GNU-only and left this scan silently disabled (fail-OPEN) on
  # macOS. Window rounds UP to the whole minute: exact at the 7200s
  # default, and <60s wider for odd overrides — i.e. fail-SAFE for an
  # ownership gate. Full rationale: hooks/lib/portable-time.sh.
  # (Comments here are kept short on purpose: this file is re-parsed on
  # every PreToolUse call and ~2 KB of prose measured ~1 ms/call.)
  fresh_min=$(( (COG_CLAIM_FRESH_SECONDS + 59) / 60 ))
  [[ "$fresh_min" -gt 0 ]] || fresh_min=1
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    br=$(sed -nE 's/.*"branch"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -1)
    wt=$(sed -nE 's/.*"worktree"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -1)
    rid=$(sed -nE 's/.*"repo"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -1)
    [[ -z "$br" ]] && continue
    if [[ -z "$rid" ]]; then
      # Pre-repo-scoping schema (no "repo" field): SKIP, fail-open — a
      # missing field on a same-machine fresh claim is ambiguous, and
      # foreign-repo claims must never block (see KNOWN LIMITS). The live
      # owning session re-scopes its claim at its next write/refresh.
      echo "[concurrent-ownership-gate] note: claim $(basename "$f") has no repo field (old schema) — skipped, not enforced." >&2
      continue
    fi
    if [[ "$rid" != "$cur_repo_id" ]] && [[ "$(_norm_path "$rid")" != "$(_norm_path "$cur_repo_id")" ]]; then
      continue  # foreign-repo claim — another repo's ownership state
    fi
    if [[ -n "$wt" ]] && [[ "$(_norm_path "$wt")" == "$root_norm" ]]; then
      continue  # our own session's claim
    fi
    CLAIM_BRANCHES+=("$br")
    CLAIM_WORKTREES+=("${wt:-unknown}")
  done < <(find "$COG_CLAIMS_DIR" -maxdepth 1 -type f -name '*.json' -mmin "-${fresh_min}" 2>/dev/null)
}

# Is plan slug $1 owned by another live session? Returns 0 and sets
# OWNER_KIND (worktree|claim), OWNER_PATH, OWNER_BRANCH when owned.
_check_slug_owner() {
  local slug="$1" core cur_branch i
  OWNER_KIND=""; OWNER_PATH=""; OWNER_BRANCH=""
  core=$(_slug_core "$slug")
  [[ ${#core} -lt 4 ]] && return 1  # too short to match reliably; fail open
  cur_branch=$(git -C "$REPO_ROOT" symbolic-ref --short -q HEAD 2>/dev/null || echo "")
  if [[ -n "$cur_branch" ]] && [[ "$cur_branch" == *"$core"* ]]; then
    return 1  # our own plan — mutation is the normal close/defer flow
  fi
  for ((i=0; i<${#OTHER_WT_BRANCHES[@]}; i++)); do
    if [[ "${OTHER_WT_BRANCHES[$i]}" == *"$core"* ]]; then
      OWNER_KIND="worktree"
      OWNER_PATH="${OTHER_WT_PATHS[$i]}"
      OWNER_BRANCH="${OTHER_WT_BRANCHES[$i]}"
      return 0
    fi
  done
  for ((i=0; i<${#CLAIM_BRANCHES[@]}; i++)); do
    if [[ "${CLAIM_BRANCHES[$i]}" == *"$core"* ]]; then
      OWNER_KIND="claim"
      OWNER_PATH="${CLAIM_WORKTREES[$i]}"
      OWNER_BRANCH="${CLAIM_BRANCHES[$i]}"
      return 0
    fi
  done
  return 1
}

# Is branch $1 checked out in another worktree or freshly claimed elsewhere?
_check_branch_owner() {
  local target="$1" i
  OWNER_KIND=""; OWNER_PATH=""; OWNER_BRANCH=""
  target="${target#refs/heads/}"
  for ((i=0; i<${#OTHER_WT_BRANCHES[@]}; i++)); do
    if [[ "${OTHER_WT_BRANCHES[$i]}" == "$target" ]]; then
      OWNER_KIND="worktree"
      OWNER_PATH="${OTHER_WT_PATHS[$i]}"
      OWNER_BRANCH="${OTHER_WT_BRANCHES[$i]}"
      return 0
    fi
  done
  for ((i=0; i<${#CLAIM_BRANCHES[@]}; i++)); do
    if [[ "${CLAIM_BRANCHES[$i]}" == "$target" ]]; then
      OWNER_KIND="claim"
      OWNER_PATH="${CLAIM_WORKTREES[$i]}"
      OWNER_BRANCH="${CLAIM_BRANCHES[$i]}"
      return 0
    fi
  done
  return 1
}

# ============================================================
# Waiver (house pattern: fresh <1h, purpose clauses, target-scoped)
# ============================================================

# Echo the first fresh, purpose-clause-valid waiver file covering target $1
# (matched as a substring of the waiver text). Returns 1 if none.
_has_fresh_waiver() {
  local target="$1" state_dir f
  state_dir="$REPO_ROOT/.claude/state"
  [[ -d "$state_dir" ]] || return 1
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if declare -F waiver_has_purpose_clauses >/dev/null 2>&1; then
      waiver_has_purpose_clauses "$f" || continue
    else
      continue  # lib missing → fail closed (no waiver honored)
    fi
    grep -qF "$target" "$f" 2>/dev/null || continue
    printf '%s' "$f"
    return 0
  done < <(find "$state_dir" -maxdepth 1 -type f -name 'concurrent-ownership-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null)
  return 1
}

# ============================================================
# Block emitter
# ============================================================

# _block <operation-description> <target> — uses OWNER_KIND/PATH/BRANCH.
# The ONE decision/emit site both the enforce path and the entry's --check
# pre-flight mode reach (GC_MODE, set once above from the entry's frozen
# argv[1] — see the top-of-file note). Same fields, same code path, either
# way: drift between what this gate enforces and what --check reports is
# structurally impossible.
_block() {
  local op="$1" target="$2"
  local signal
  if [[ "$OWNER_KIND" == "worktree" ]]; then
    signal="the target's branch is checked out in that worktree right now (git worktree list)"
  else
    signal="a fresh (<$((COG_CLAIM_FRESH_SECONDS / 3600))h) session claim covers the target (claims dir: $COG_CLAIMS_DIR)"
  fi
  if [[ "$GC_MODE" != "check" ]]; then
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "concurrent-ownership-gate" "block" "op=$op target=$target owner_kind=$OWNER_KIND owner_path=$OWNER_PATH owner_branch=$OWNER_BRANCH"
  fi
  {
    echo "================================================================"
    echo "$(gc_header "CONCURRENT-OWNERSHIP GATE — BLOCKED" "$GC_MODE")"
    echo "================================================================"
    echo ""
    gc_block \
      "mutation blocked — $op on '$target' is owned by another live session" \
      "docs/plans/ and branches are SHARED state that concurrent sessions read and write; mutating a target another live session owns yanks the work out from under it (docs/lessons/2026-07-11-bulk-shared-state-mutation-without-ownership-check.md)" \
      "see who is live ('git worktree list' / 'bash ~/.claude/scripts/broadcast-active-session.sh check'), then coordinate with the owning session or exclude the owned target from a bulk op — see the coordination path below" \
      "a fresh (<1h) structured waiver naming both purpose clauses and the target at <repo>/.claude/state/concurrent-ownership-waiver-*.txt (cost: unlocks THIS target for <1h, ledger-logged) — see the Hatch section below"
    echo ""
    echo "Operation: $op"
    echo "Target:    $target"
    echo ""
    echo "OWNED BY ANOTHER LIVE SESSION:"
    echo "  worktree: $OWNER_PATH"
    echo "  branch:   $OWNER_BRANCH"
    echo "  signal:   $signal"
    echo ""
    echo "Why: docs/plans/ and branches are SHARED state that concurrent"
    echo "sessions read and write. Mutating a plan/branch another live session"
    echo "owns yanks the work out from under it — this is the exact incident in"
    echo "docs/lessons/2026-07-11-bulk-shared-state-mutation-without-ownership-check.md."
    echo ""
    echo "NOTE: this block stopped the ENTIRE command from running — no part of"
    echo "it executed (including any unrelated segments chained with && or ;)."
    echo "After remediation, re-run the FULL command."
    echo ""
    echo "Coordination path (in order):"
    echo "  1. See who is live:"
    echo "       git worktree list"
    echo "       bash ~/.claude/scripts/broadcast-active-session.sh check"
    echo "  2. If the owning worktree is finished/abandoned work of YOURS:"
    echo "     close it properly first (merge or close its plan, then"
    echo "     \`git worktree remove $OWNER_PATH\`), then re-run this command."
    echo "     (That removal can itself re-block if a fresh claim still covers"
    echo "     the worktree — the SAME waiver below covers both operations, as"
    echo "     it is matched on the target string, not the command.)"
    echo "  3. If another session is actively building it: coordinate via the"
    echo "     orchestrator — do NOT mutate its plan/branch."
    echo "  4. Bulk operations: re-run per-file, EXCLUDING the owned target(s)."
    echo "     (Verify each member before mutating — 'everything ACTIVE' is not"
    echo "     the same set as 'the stale ones'.)"
    echo ""
    echo "Hatch (cost: unlocks THIS target for <1h, ledger-logged): a genuine,"
    echo "verified need to mutate the owned target anyway (e.g. the owning"
    echo "worktree is confirmed dead and unremovable right now) gets a fresh"
    echo "(<1h) structured waiver naming BOTH purpose clauses AND the target:"
    echo "  mkdir -p \"$REPO_ROOT/.claude/state\""
    echo "  {"
    echo "    echo \"Purpose: this gate exists to prevent mutating plan/branch state owned by another live session\""
    echo "    echo \"Because: <why that does not apply to this specific target>\""
    echo "    echo \"Target: $target\""
    if [[ -n "$OWNER_BRANCH" ]] && [[ "$target" != *"$OWNER_BRANCH"* ]]; then
      echo "    echo \"Target: $OWNER_BRANCH\""
    fi
    echo "  } > \"$REPO_ROOT/.claude/state/concurrent-ownership-waiver-\$(date +%s).txt\""
    echo "Then re-run the command. (Waivers match on the target string, so this"
    echo "one waiver also covers a follow-up \`git worktree remove\` re-block on"
    echo "the same branch.)"
    echo ""
    echo "This gate: ~/.claude/hooks/concurrent-ownership-gate.sh (source: adapters/claude-code/hooks/concurrent-ownership-gate.sh)"
    echo "================================================================"
  } >&2
  if [[ "$GC_MODE" != "check" ]]; then
    cat <<'JSON'
{"decision": "block", "reason": "concurrent-ownership-gate: the mutation target (plan/branch/worktree) is owned by another live session. See stderr for the owning worktree, the coordination path, and the structured waiver hatch."}
JSON
  fi
  exit "$(gc_exit_code "$GC_MODE" 2)"
}

# Combined check-then-block for a plan slug: waiver → allow; owned → block.
_guard_slug() {
  local op="$1" slug="$2" core wfile
  if _check_slug_owner "$slug"; then
    core=$(_slug_core "$slug")
    if wfile=$(_has_fresh_waiver "$core") || wfile=$(_has_fresh_waiver "$slug"); then
      command -v ledger_emit >/dev/null 2>&1 && ledger_emit "concurrent-ownership-gate" "waiver" "op=$op target=$slug waiver=$wfile"
      # Workaround-as-sensor law (operator directive): a sanctioned escape's
      # USE is itself a signal — ledger it via gc_escape_used regardless of
      # this ledger_emit call's own success (spawn-free, never blocks; see
      # gate-contract-lib.sh's own header).
      declare -F gc_escape_used >/dev/null 2>&1 && gc_escape_used "concurrent-ownership-gate" "waiver-file" "target=$slug" "op=$op waiver=$wfile"
      echo "[concurrent-ownership-gate] ALLOW: fresh structured waiver covers owned target '$slug' ($wfile) — ledger-logged." >&2
      return 0
    fi
    _block "$op" "docs/plans/${slug}.md (slug: $slug)"
  fi
  return 0
}

# Combined check-then-block for a branch target.
_guard_branch() {
  local op="$1" branch="$2" wfile
  if _check_branch_owner "$branch"; then
    if wfile=$(_has_fresh_waiver "$branch"); then
      command -v ledger_emit >/dev/null 2>&1 && ledger_emit "concurrent-ownership-gate" "waiver" "op=$op target=$branch waiver=$wfile"
      declare -F gc_escape_used >/dev/null 2>&1 && gc_escape_used "concurrent-ownership-gate" "waiver-file" "target=$branch" "op=$op waiver=$wfile"
      echo "[concurrent-ownership-gate] ALLOW: fresh structured waiver covers owned branch '$branch' ($wfile) — ledger-logged." >&2
      return 0
    fi
    _block "$op" "branch $branch"
  fi
  return 0
}

# ============================================================
# --self-test
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  export HARNESS_SELFTEST=1

  # Portable fixture aging (M4); self-test only, never the hook path.
  . "$_COG_SELF_DIR/lib/portable-time.sh" 2>/dev/null || {
    echo "self-test: cannot source lib/portable-time.sh" >&2; exit 2; }

  # Resolve to the ENTRY file (concurrent-ownership-gate.sh), not this body
  # file: subprocess scenarios below re-invoke SELF_HOOK exactly as a real
  # PreToolUse call would, and only the entry has the relevance pre-filter +
  # --self-test/--check dispatch. _COG_ENTRY_PATH is set by the entry before
  # it sources this body (see that file); BASH_SOURCE[0] here would resolve
  # to THIS body file if that variable were ever absent, which would test
  # the wrong artifact — the fallback exists only for a direct `bash
  # concurrent-ownership-gate-body.sh --self-test` debugging invocation.
  SELF_HOOK="${_COG_ENTRY_PATH:-$_COG_SELF_DIR/$(basename "${BASH_SOURCE[0]}")}"
  if [[ ! -f "$SELF_HOOK" ]]; then
    echo "self-test: cannot resolve own path" >&2
    exit 2
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "self-test: jq required" >&2
    exit 2
  fi

  PASSED=0
  FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t cogst)
  trap 'rm -rf "$TMPROOT"' EXIT

  # Full sandbox: claims + ledger never touch real state.
  export COG_CLAIMS_DIR="$TMPROOT/claims"
  export SIGNAL_LEDGER_PATH="$TMPROOT/ledger.jsonl"
  # Workaround-as-sensor sandbox (gc_escape_used -> ws_record): same
  # never-touch-real-state discipline as SIGNAL_LEDGER_PATH above.
  # HARNESS_SELFTEST=1 is already exported at the top of this block.
  export WORKAROUND_SENSOR_LEDGER_PATH="$TMPROOT/ws-ledger.jsonl"
  mkdir -p "$COG_CLAIMS_DIR"

  MAIN="$TMPROOT/main"
  mkdir -p "$MAIN/docs/plans"
  (
    cd "$MAIN" || exit 99
    git init -q 2>/dev/null
    git config core.hooksPath "" 2>/dev/null
    git config user.email "test@example.com" 2>/dev/null
    git config user.name "Test" 2>/dev/null
    git config commit.gpgsign false 2>/dev/null
    for slug in owned-plan-2026-07-11 unowned-plan-2026-07-10 claimed-plan-2026-07-09; do
      printf '# Plan: %s\nStatus: ACTIVE\n\n## Goal\nfixture\n' "$slug" > "docs/plans/${slug}.md"
    done
    git add -A 2>/dev/null
    git commit -q -m "init fixture plans" 2>/dev/null
    git branch feat/owned-plan 2>/dev/null
    git worktree add "$TMPROOT/wt-owned" feat/owned-plan >/dev/null 2>&1
  )
  if [[ ! -d "$TMPROOT/wt-owned" ]]; then
    echo "self-test: fixture worktree creation failed" >&2
    exit 2
  fi
  # Repo identity of the fixture repo (no origin remote → git common dir),
  # exactly what _repo_identity computes at gate runtime. Claim fixtures
  # carry it so they read as THIS repo's claims (claims are repo-scoped).
  MAIN_REPO_ID=$(git -C "$MAIN" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [[ -z "$MAIN_REPO_ID" ]]; then
    echo "self-test: cannot resolve fixture repo identity" >&2
    exit 2
  fi

  # Run the hook with a Bash-tool command payload from a given cwd.
  # $1=cwd  $2=command  → echoes rc; stderr saved to $TMPROOT/last-stderr
  _run_cmd() {
    local cwd="$1" cmd="$2" input rc
    input=$(jq -cn --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
    ( cd "$cwd" && printf '%s' "$input" | bash "$SELF_HOOK" >"$TMPROOT/last-stdout" 2>"$TMPROOT/last-stderr" )
    rc=$?
    echo "$rc"
  }

  # Same but with an arbitrary tool payload JSON.
  _run_payload() {
    local cwd="$1" input="$2" rc
    ( cd "$cwd" && printf '%s' "$input" | bash "$SELF_HOOK" >"$TMPROOT/last-stdout" 2>"$TMPROOT/last-stderr" )
    rc=$?
    echo "$rc"
  }

  _report() {
    local label="$1" ok="$2" detail="${3:-}"
    if [[ "$ok" -eq 1 ]]; then
      echo "self-test ($label): PASS" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test ($label): FAIL $detail" >&2
      FAILED=$((FAILED+1))
    fi
  }

  BULK_CMD='for f in docs/plans/*.md; do sed -i "s/^Status: ACTIVE/Status: DEFERRED/" "$f"; done'

  # ---- 1: GOLDEN — bulk defer including a worktree-owned plan → BLOCK naming the worktree ----
  RC=$(_run_cmd "$MAIN" "$BULK_CMD")
  ERR=$(cat "$TMPROOT/last-stderr" 2>/dev/null)
  OK=0
  if [[ "$RC" == "2" ]] && [[ "$ERR" == *"wt-owned"* ]] && [[ "$ERR" == *"feat/owned-plan"* ]]; then OK=1; fi
  _report "1 golden-bulk-defer-blocks-naming-worktree" "$OK" "(rc=$RC, expected 2 + stderr naming wt-owned/feat/owned-plan)"

  # ---- 2: clean pass — single Status flip of an UNOWNED plan → ALLOW ----
  RC=$(_run_cmd "$MAIN" 'sed -i "s/^Status: ACTIVE/Status: DEFERRED/" docs/plans/unowned-plan-2026-07-10.md')
  OK=0; [[ "$RC" == "0" ]] && OK=1
  _report "2 unowned-single-flip-allowed" "$OK" "(rc=$RC, expected 0)"

  # ---- 3: waiver honored — fresh purpose-clause waiver naming the target → ALLOW + ledger ----
  mkdir -p "$MAIN/.claude/state"
  {
    echo "Purpose: this gate exists to prevent mutating plan/branch state owned by another live session"
    echo "Because: self-test fixture — the owning worktree is a synthetic fixture, not a live session"
    echo "Target: owned-plan"
  } > "$MAIN/.claude/state/concurrent-ownership-waiver-selftest.txt"
  RC=$(_run_cmd "$MAIN" "$BULK_CMD")
  OK=0
  if [[ "$RC" == "0" ]] && grep -q '"gate":"concurrent-ownership-gate"' "$SIGNAL_LEDGER_PATH" 2>/dev/null \
     && grep -q '"event":"waiver"' "$SIGNAL_LEDGER_PATH" 2>/dev/null; then OK=1; fi
  _report "3 waiver-honored-and-ledger-logged" "$OK" "(rc=$RC, expected 0 + waiver ledger entry)"

  # ---- 4: stale waiver (>1h) rejected → BLOCK ----
  # Was GNU-only `touch -d`, no fallback: on macOS the waiver stayed
  # fresh and this scenario silently tested the fresh-waiver path.
  nl_touch_age "$MAIN/.claude/state/concurrent-ownership-waiver-selftest.txt" 7200 \
    || { echo "self-test: could not backdate stale-waiver fixture" >&2; exit 2; }
  RC=$(_run_cmd "$MAIN" "$BULK_CMD")
  OK=0; [[ "$RC" == "2" ]] && OK=1
  _report "4 stale-waiver-rejected" "$OK" "(rc=$RC, expected 2)"
  rm -f "$MAIN/.claude/state/concurrent-ownership-waiver-selftest.txt"

  # ---- 5: weak waiver (no purpose clauses) rejected → BLOCK ----
  echo "Target: owned-plan" > "$MAIN/.claude/state/concurrent-ownership-waiver-weak.txt"
  RC=$(_run_cmd "$MAIN" "$BULK_CMD")
  OK=0; [[ "$RC" == "2" ]] && OK=1
  _report "5 clause-less-waiver-rejected" "$OK" "(rc=$RC, expected 2)"
  rm -f "$MAIN/.claude/state/concurrent-ownership-waiver-weak.txt"

  # ---- 6: Edit-tool payload flipping the owned plan's Status → BLOCK ----
  INPUT=$(jq -cn --arg fp "$MAIN/docs/plans/owned-plan-2026-07-11.md" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"Status: ACTIVE",new_string:"Status: DEFERRED"}}')
  RC=$(_run_payload "$MAIN" "$INPUT")
  ERR=$(cat "$TMPROOT/last-stderr" 2>/dev/null)
  OK=0
  if [[ "$RC" == "2" ]] && [[ "$ERR" == *"wt-owned"* ]]; then OK=1; fi
  _report "6 edit-payload-owned-status-flip-blocked" "$OK" "(rc=$RC, expected 2 naming worktree)"

  # ---- 7: Edit-tool payload on one's OWN plan from its owning worktree → ALLOW ----
  INPUT=$(jq -cn --arg fp "$TMPROOT/wt-owned/docs/plans/owned-plan-2026-07-11.md" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"Status: ACTIVE",new_string:"Status: COMPLETED"}}')
  RC=$(_run_payload "$TMPROOT/wt-owned" "$INPUT")
  OK=0; [[ "$RC" == "0" ]] && OK=1
  _report "7 own-plan-edit-from-owning-worktree-allowed" "$OK" "(rc=$RC, expected 0)"

  # ---- 8: git branch -D of the other-worktree branch → BLOCK ----
  RC=$(_run_cmd "$MAIN" 'git branch -D feat/owned-plan')
  ERR=$(cat "$TMPROOT/last-stderr" 2>/dev/null)
  OK=0
  if [[ "$RC" == "2" ]] && [[ "$ERR" == *"feat/owned-plan"* ]]; then OK=1; fi
  _report "8 branch-delete-of-checked-out-branch-blocked" "$OK" "(rc=$RC, expected 2)"

  # ---- 9: git worktree remove under a fresh other-session claim → BLOCK ----
  cat > "$COG_CLAIMS_DIR/feat-owned-plan.json" <<CLAIMJSON
{"branch":"feat/owned-plan","plan":"owned-plan","worktree":"$TMPROOT/wt-owned","repo":"$MAIN_REPO_ID","hostname":"selftest-host","iso_timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
CLAIMJSON
  RC=$(_run_cmd "$MAIN" "git worktree remove $TMPROOT/wt-owned")
  OK=0; [[ "$RC" == "2" ]] && OK=1
  _report "9 worktree-remove-of-claimed-worktree-blocked" "$OK" "(rc=$RC, expected 2)"
  rm -f "$COG_CLAIMS_DIR/feat-owned-plan.json"

  # ---- 10: worktree remove with NO fresh claim → ALLOW (existence alone never blocks) ----
  RC=$(_run_cmd "$MAIN" "git worktree remove $TMPROOT/wt-owned")
  OK=0; [[ "$RC" == "0" ]] && OK=1
  _report "10 worktree-remove-unclaimed-allowed" "$OK" "(rc=$RC, expected 0)"

  # ---- 11: claim-based plan ownership (no worktree checkout) → BLOCK ----
  cat > "$COG_CLAIMS_DIR/feat-claimed-plan.json" <<CLAIMJSON
{"branch":"feat/claimed-plan","plan":"claimed-plan","worktree":"$TMPROOT/elsewhere","repo":"$MAIN_REPO_ID","hostname":"selftest-host","iso_timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
CLAIMJSON
  RC=$(_run_cmd "$MAIN" 'sed -i "s/^Status: ACTIVE/Status: DEFERRED/" docs/plans/claimed-plan-2026-07-09.md')
  ERR=$(cat "$TMPROOT/last-stderr" 2>/dev/null)
  OK=0
  if [[ "$RC" == "2" ]] && [[ "$ERR" == *"feat/claimed-plan"* ]]; then OK=1; fi
  _report "11 fresh-claim-ownership-blocks" "$OK" "(rc=$RC, expected 2 naming claimed branch)"

  # ---- 12: STALE claim (backdated mtime) does NOT block → ALLOW ----
  # Was GNU-only `touch -d`: on macOS the claim stayed FRESH and this
  # scenario only reported PASS because the sibling `date -d` bug had
  # disabled the scan entirely — two failures cancelling into a green.
  nl_touch_age "$COG_CLAIMS_DIR/feat-claimed-plan.json" 10800 \
    || { echo "self-test: could not backdate stale-claim fixture" >&2; exit 2; }
  RC=$(_run_cmd "$MAIN" 'sed -i "s/^Status: ACTIVE/Status: DEFERRED/" docs/plans/claimed-plan-2026-07-09.md')
  OK=0; [[ "$RC" == "0" ]] && OK=1
  _report "12 stale-claim-ignored" "$OK" "(rc=$RC, expected 0)"
  rm -f "$COG_CLAIMS_DIR/feat-claimed-plan.json"

  # ---- 13: read-only bulk (grep, no mutation indicator) → ALLOW ----
  RC=$(_run_cmd "$MAIN" 'grep -lE "^Status: ACTIVE" docs/plans/*.md')
  OK=0; [[ "$RC" == "0" ]] && OK=1
  _report "13 read-only-bulk-allowed" "$OK" "(rc=$RC, expected 0)"

  # ---- 14: unrelated command → ALLOW (passthrough) ----
  RC=$(_run_cmd "$MAIN" 'git commit -m "normal work"')
  OK=0; [[ "$RC" == "0" ]] && OK=1
  _report "14 unrelated-command-passthrough" "$OK" "(rc=$RC, expected 0)"

  # ---- 15: git mv of the owned plan into deferred/ → BLOCK ----
  RC=$(_run_cmd "$MAIN" 'git mv docs/plans/owned-plan-2026-07-11.md docs/plans/deferred/')
  OK=0; [[ "$RC" == "2" ]] && OK=1
  _report "15 git-mv-owned-plan-blocked" "$OK" "(rc=$RC, expected 2)"

  # ---- 16: PowerShell tool_name parses identically → BLOCK on golden bulk ----
  INPUT=$(jq -cn --arg cmd "$BULK_CMD" '{tool_name:"PowerShell",tool_input:{command:$cmd}}')
  RC=$(_run_payload "$MAIN" "$INPUT")
  OK=0; [[ "$RC" == "2" ]] && OK=1
  _report "16 powershell-tool-parsed" "$OK" "(rc=$RC, expected 2)"

  # ---- 17: cd-tracking — command cds into the repo first → BLOCK ----
  RC=$(_run_cmd "$TMPROOT" "cd $MAIN && $BULK_CMD")
  OK=0; [[ "$RC" == "2" ]] && OK=1
  _report "17 cd-tracked-target-repo" "$OK" "(rc=$RC, expected 2)"

  # ---- 18: fresh claim from a FOREIGN repo → ALLOW (claims are repo-scoped) ----
  # Same shape as scenario 11 but the claim's repo identity points at a
  # DIFFERENT repo — machine-global claims must not cross repo boundaries.
  cat > "$COG_CLAIMS_DIR/feat-claimed-plan.json" <<CLAIMJSON
{"branch":"feat/claimed-plan","plan":"claimed-plan","worktree":"$TMPROOT/elsewhere","repo":"/somewhere/else/entirely/.git","hostname":"selftest-host","iso_timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
CLAIMJSON
  RC=$(_run_cmd "$MAIN" 'sed -i "s/^Status: ACTIVE/Status: DEFERRED/" docs/plans/claimed-plan-2026-07-09.md')
  OK=0; [[ "$RC" == "0" ]] && OK=1
  _report "18 foreign-repo-claim-does-not-block" "$OK" "(rc=$RC, expected 0)"
  rm -f "$COG_CLAIMS_DIR/feat-claimed-plan.json"

  # ---- 19: prose edit mentioning '## Status quo' on an OWNED plan → ALLOW ----
  # 'Status' with no terminal-state token is prose, not a terminal flip.
  RC=$(_run_cmd "$MAIN" 'sed -i "s/^## Status quo/## Status quo (revised)/" docs/plans/owned-plan-2026-07-11.md')
  OK=0; [[ "$RC" == "0" ]] && OK=1
  _report "19 owned-plan-prose-status-quo-edit-allowed" "$OK" "(rc=$RC, expected 0)"

  # ---- 20: --check pre-flight on the golden bulk-defer → WOULD BLOCK (rc=1),
  # same structured fields + owner naming as enforce, and the ledger gains NO
  # new "block" row (a --check run must never look like a real enforcement
  # event downstream). Gate Philosophy Law (R3.4): one decision, two modes.
  _run_cmd_check() {
    local cwd="$1" cmd="$2" input rc
    input=$(jq -cn --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
    ( cd "$cwd" && printf '%s' "$input" | bash "$SELF_HOOK" --check >"$TMPROOT/last-stdout" 2>"$TMPROOT/last-stderr" )
    rc=$?
    echo "$rc"
  }
  LEDGER_BLOCK_COUNT_BEFORE=$(grep -c '"event":"block"' "$SIGNAL_LEDGER_PATH" 2>/dev/null || echo 0)
  RC=$(_run_cmd_check "$MAIN" "$BULK_CMD")
  ERR=$(cat "$TMPROOT/last-stderr" 2>/dev/null)
  LEDGER_BLOCK_COUNT_AFTER=$(grep -c '"event":"block"' "$SIGNAL_LEDGER_PATH" 2>/dev/null || echo 0)
  OK=0
  if [[ "$RC" == "1" ]] \
     && [[ "$ERR" == *"WOULD BLOCK (--check pre-flight, not enforced)"* ]] \
     && [[ "$ERR" == *"[GATE:WHAT]"* ]] && [[ "$ERR" == *"[GATE:WHY]"* ]] \
     && [[ "$ERR" == *"[GATE:FIX]"* ]] && [[ "$ERR" == *"[GATE:ESCAPE]"* ]] \
     && [[ "$ERR" == *"wt-owned"* ]] && [[ "$ERR" == *"feat/owned-plan"* ]] \
     && [[ "$LEDGER_BLOCK_COUNT_AFTER" == "$LEDGER_BLOCK_COUNT_BEFORE" ]]; then
    OK=1
  fi
  _report "20 check-mode-would-block-same-fields-no-ledger-write" "$OK" "(rc=$RC, expected 1 + WOULD BLOCK + 4 fields + owner naming + ledger unchanged: $LEDGER_BLOCK_COUNT_BEFORE -> $LEDGER_BLOCK_COUNT_AFTER)"

  # ---- 21: --check pre-flight on a clean pass (unowned single flip) →
  # would-pass, exit 0, identical to enforce's own scenario 2 outcome.
  RC=$(_run_cmd_check "$MAIN" 'sed -i "s/^Status: ACTIVE/Status: DEFERRED/" docs/plans/unowned-plan-2026-07-10.md')
  OK=0; [[ "$RC" == "0" ]] && OK=1
  _report "21 check-mode-clean-pass-allowed" "$OK" "(rc=$RC, expected 0)"

  # ---- 22: workaround-as-sensor — a waiver-honored ALLOW (same fixture as
  # scenario 3) both (a) still honors the waiver identically (verdict
  # unchanged, rc=0) AND (b) appends a row to the workaround-sensor ledger
  # (gc_escape_used -> ws_record), independent of the pre-existing
  # signal-ledger "waiver" event scenario 3 already asserts. Confirms the
  # operator's workaround-as-sensor law is wired end-to-end at this gate's
  # waiver-honored call site, not just a self-tested-in-isolation library.
  {
    echo "Purpose: this gate exists to prevent mutating plan/branch state owned by another live session"
    echo "Because: self-test fixture — the owning worktree is a synthetic fixture, not a live session"
    echo "Target: owned-plan"
  } > "$MAIN/.claude/state/concurrent-ownership-waiver-selftest22.txt"
  rm -f "$WORKAROUND_SENSOR_LEDGER_PATH"
  RC=$(_run_cmd "$MAIN" "$BULK_CMD")
  OK=0
  if [[ "$RC" == "0" ]] \
     && grep -q '"gate":"concurrent-ownership-gate"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null \
     && grep -q '"bypass_kind":"waiver-file"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null \
     && grep -q '"command_fingerprint":"target=owned-plan-2026-07-11"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null; then
    OK=1
  fi
  _report "22 workaround-sensor-ledger-row-on-waiver-honored" "$OK" "(rc=$RC, expected 0 + workaround-sensor ledger row)"
  rm -f "$MAIN/.claude/state/concurrent-ownership-waiver-selftest22.txt"

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of $((PASSED+FAILED)) scenarios)" >&2
  [[ "$FAILED" -eq 0 ]] && exit 0 || exit 2
fi

# ============================================================
# Main hook logic
# ============================================================

# --- P1 perf metering (perf-telemetry-2026-07 plan) -------------------------
# Self-metering: one of the 5 highest-cost per-Bash-call hooks (no single
# PreToolUse chain wrapper exists — see hooks/lib/perf-ledger.sh's header
# for the PROVEN instrumentation-point finding). Builtin-only, zero forks;
# a trap on EXIT covers every exit path below (including the cheap
# pre-filter further down) without touching each one individually.
source "$_COG_SELF_DIR/lib/perf-ledger.sh" 2>/dev/null || true
if declare -F pl_meter_begin >/dev/null 2>&1; then
  pl_meter_begin
  trap 'pl_meter_end "concurrent-ownership-gate"' EXIT
fi

# --- Read tool input (env var OR stdin) ---
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]] && [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
if [[ -z "$INPUT" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0  # cannot parse safely — err toward allow (same posture as peers)
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

# ------------------------------------------------------------
# Edit / Write / MultiEdit payloads: a Status flip on docs/plans/*.md
# ------------------------------------------------------------
if [[ "$TOOL_NAME" == "Edit" ]] || [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "MultiEdit" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .file_path // ""' 2>/dev/null)
  [[ -z "$FILE_PATH" ]] && exit 0
  FP_FWD="${FILE_PATH//\\//}"
  # Top-level docs/plans/*.md only (archive/deferred moves are terminal-state
  # bookkeeping handled by plan-lifecycle; subdir files are not live plans).
  case "$FP_FWD" in
    *docs/plans/*/*) exit 0 ;;
    *docs/plans/*.md) : ;;
    *) exit 0 ;;
  esac
  [[ -f "$FILE_PATH" ]] || exit 0  # brand-new plan file — nothing to own yet

  NEW_CONTENT=$(echo "$INPUT" | jq -r '
    if .tool_input.edits then ([.tool_input.edits[].new_string // ""] | join("\n"))
    else (.tool_input.new_string // .tool_input.content // "")
    end' 2>/dev/null)
  if ! printf '%s' "$NEW_CONTENT" | grep -qE 'Status:[[:space:]]*(DEFERRED|COMPLETED|ABANDONED|SUPERSEDED)'; then
    exit 0  # not a terminal-status flip
  fi

  FILE_DIR=$(dirname "$FILE_PATH" 2>/dev/null || echo "")
  REPO_ROOT=$(cd "$FILE_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "")
  [[ -z "$REPO_ROOT" ]] && exit 0

  SLUG=$(basename "$FP_FWD")
  SLUG="${SLUG%.md}"
  _load_other_worktrees
  _load_fresh_claims
  _guard_slug "$TOOL_NAME status-flip of docs/plans/${SLUG}.md" "$SLUG"
  exit 0
fi

# ------------------------------------------------------------
# Bash / PowerShell command strings
# ------------------------------------------------------------
if [[ "$TOOL_NAME" != "Bash" ]] && [[ "$TOOL_NAME" != "PowerShell" ]]; then
  exit 0
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

# Cheap pre-filter: nothing this gate guards is mentioned → pass.
if ! echo "$CMD" | grep -qE 'docs/plans|git[[:space:]].*(branch|worktree)|worktree[[:space:]]+remove'; then
  exit 0
fi

# --- Walk segments: track cd/Set-Location; analyze git segments ---
CD_TARGET=""
GIT_MV_SEEN=0
declare -a BRANCH_DELETE_TARGETS=()
declare -a BRANCH_DELETE_DIRS=()
WT_REMOVE_TARGET=""
WT_REMOVE_DIR=""

TMP_CMD=$(echo "$CMD" | sed -e 's/&&/\n/g' -e 's/;/\n/g')
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  seg="${seg%"${seg##*[![:space:]]}"}"
  [[ -z "$seg" ]] && continue
  if [[ "$seg" =~ ^cd($|[[:space:]]) ]] || [[ "$seg" =~ ^[Ss]et-[Ll]ocation($|[[:space:]]) ]]; then
    CD_TARGET=$(_parse_cd_target "$seg" "${CD_TARGET:-$PWD}")
    continue
  fi
  if [[ "$seg" =~ ^git([[:space:]]|$) ]]; then
    _analyze_git_generic "$seg" "${CD_TARGET:-$PWD}"
    EFF_DIR="${G_C_TARGET:-${CD_TARGET:-$PWD}}"
    case "$G_SUB" in
      mv)
        GIT_MV_SEEN=1
        ;;
      branch)
        DEL=0
        SEG_BRANCH_TARGETS=()
        for a in "${G_ARGS[@]}"; do
          case "$a" in
            -D|-d|--delete) DEL=1 ;;
            -*) : ;;
            *) SEG_BRANCH_TARGETS+=("$a") ;;
          esac
        done
        if [[ "$DEL" -eq 1 ]]; then
          for b in "${SEG_BRANCH_TARGETS[@]}"; do
            BRANCH_DELETE_TARGETS+=("$b")
            BRANCH_DELETE_DIRS+=("$EFF_DIR")
          done
        fi
        ;;
      worktree)
        if [[ "${G_ARGS[0]:-}" == "remove" ]]; then
          for ((wi=1; wi<${#G_ARGS[@]}; wi++)); do
            case "${G_ARGS[$wi]}" in
              -*) : ;;
              *) WT_REMOVE_TARGET=$(_compose_dir "" "$EFF_DIR" "${G_ARGS[$wi]}"); WT_REMOVE_DIR="$EFF_DIR"; break ;;
            esac
          done
        fi
        ;;
    esac
  fi
done <<< "$TMP_CMD"

EFFECTIVE_DIR="${CD_TARGET:-$PWD}"

# --- (c) branch deletion of a branch owned elsewhere ---
if [[ "${#BRANCH_DELETE_TARGETS[@]}" -gt 0 ]]; then
  for ((bi=0; bi<${#BRANCH_DELETE_TARGETS[@]}; bi++)); do
    REPO_ROOT=$(git -C "${BRANCH_DELETE_DIRS[$bi]}" rev-parse --show-toplevel 2>/dev/null || echo "")
    [[ -z "$REPO_ROOT" ]] && continue
    _load_other_worktrees
    _load_fresh_claims
    _guard_branch "git branch -D" "${BRANCH_DELETE_TARGETS[$bi]}"
  done
fi

# --- (c) worktree removal of a freshly-claimed worktree ---
if [[ -n "$WT_REMOVE_TARGET" ]]; then
  REPO_ROOT=$(git -C "$WT_REMOVE_DIR" rev-parse --show-toplevel 2>/dev/null || echo "")
  if [[ -n "$REPO_ROOT" ]]; then
    _load_other_worktrees
    _load_fresh_claims
    WT_NORM=$(_norm_path "$WT_REMOVE_TARGET")
    # Resolve the branch checked out at the worktree being removed.
    WT_BRANCH=""
    for ((wj=0; wj<${#OTHER_WT_PATHS[@]}; wj++)); do
      if [[ "$(_norm_path "${OTHER_WT_PATHS[$wj]}")" == "$WT_NORM" ]]; then
        WT_BRANCH="${OTHER_WT_BRANCHES[$wj]}"
        break
      fi
    done
    OWNED=0
    for ((wj=0; wj<${#CLAIM_BRANCHES[@]}; wj++)); do
      if [[ "$(_norm_path "${CLAIM_WORKTREES[$wj]}")" == "$WT_NORM" ]] \
         || { [[ -n "$WT_BRANCH" ]] && [[ "${CLAIM_BRANCHES[$wj]}" == "$WT_BRANCH" ]]; }; then
        OWNER_KIND="claim"
        OWNER_PATH="${CLAIM_WORKTREES[$wj]}"
        OWNER_BRANCH="${CLAIM_BRANCHES[$wj]}"
        OWNED=1
        break
      fi
    done
    if [[ "$OWNED" -eq 1 ]]; then
      if WFILE=$(_has_fresh_waiver "${WT_BRANCH:-$WT_REMOVE_TARGET}"); then
        command -v ledger_emit >/dev/null 2>&1 && ledger_emit "concurrent-ownership-gate" "waiver" "op=worktree-remove target=$WT_REMOVE_TARGET waiver=$WFILE"
        declare -F gc_escape_used >/dev/null 2>&1 && gc_escape_used "concurrent-ownership-gate" "waiver-file" "target=$WT_REMOVE_TARGET" "op=worktree-remove waiver=$WFILE"
        echo "[concurrent-ownership-gate] ALLOW: fresh structured waiver covers claimed worktree '$WT_REMOVE_TARGET' ($WFILE) — ledger-logged." >&2
      else
        _block "git worktree remove" "$WT_REMOVE_TARGET"
      fi
    fi
  fi
fi

# --- (a)/(b) plan mutations via the command string ---
MENTIONS_PLANS=0
echo "$CMD" | grep -q 'docs/plans' && MENTIONS_PLANS=1
if [[ "$MENTIONS_PLANS" -eq 1 ]]; then
  # Mutation indicators
  MUT_EDIT=0
  MUT_MV=0
  echo "$CMD" | grep -Eq '(^|[|;&[:space:]])(sed|perl|gawk|awk)[[:space:]][^|;&]*-i' && MUT_EDIT=1
  echo "$CMD" | grep -Eq '>[[:space:]]*"?docs/plans/' && MUT_EDIT=1
  echo "$CMD" | grep -Eq '(^|[|;&[:space:]])mv[[:space:]][^|;&]*docs/plans/' && MUT_MV=1
  [[ "$GIT_MV_SEEN" -eq 1 ]] && MUT_MV=1
  # Terminal-status heuristic (harness-review round 1): 'Status' alone would
  # block ANY in-place prose edit mentioning e.g. '## Status quo' on an owned
  # plan; require a terminal-state token alongside it — the gate guards
  # terminal Status flips, not prose.
  STATUS_TOUCH=0
  if echo "$CMD" | grep -q 'Status' \
     && echo "$CMD" | grep -qE 'DEFERRED|COMPLETED|ABANDONED|SUPERSEDED'; then
    STATUS_TOUCH=1
  fi

  TRIGGER=0
  if [[ "$MUT_MV" -eq 1 ]]; then
    TRIGGER=1  # moving a plan file is a mutation regardless of content
  elif [[ "$MUT_EDIT" -eq 1 ]] && [[ "$STATUS_TOUCH" -eq 1 ]]; then
    TRIGGER=1  # in-place edit that flips a Status line to a terminal state
  fi

  if [[ "$TRIGGER" -eq 1 ]]; then
    REPO_ROOT=$(git -C "$EFFECTIVE_DIR" rev-parse --show-toplevel 2>/dev/null || echo "")
    if [[ -n "$REPO_ROOT" ]] && [[ -d "$REPO_ROOT/docs/plans" ]]; then
      _load_other_worktrees
      _load_fresh_claims

      # Bulk indicator: glob over docs/plans, or a loop/xargs/find construct
      # in a command that mentions docs/plans.
      BULK=0
      case "$CMD" in
        *'docs/plans/*'*) BULK=1 ;;
      esac
      if [[ "$BULK" -eq 0 ]]; then
        echo "$CMD" | grep -Eq '(^|[;&|[:space:]])(for|while)[[:space:]]|xargs|find[[:space:]]' && BULK=1
      fi

      if [[ "$BULK" -eq 1 ]]; then
        # Concrete target list unknowable from the command string → check
        # EVERY on-disk ACTIVE top-level plan; any owned member blocks.
        for pf in "$REPO_ROOT"/docs/plans/*.md; do
          [[ -f "$pf" ]] || continue
          head -50 "$pf" 2>/dev/null | grep -q '^Status: ACTIVE' || continue
          pslug=$(basename "$pf")
          pslug="${pslug%.md}"
          _guard_slug "bulk plan mutation ($TOOL_NAME command)" "$pslug"
        done
      else
        # Specific named plan files: extract top-level docs/plans/<f>.md paths.
        while IFS= read -r ppath; do
          [[ -z "$ppath" ]] && continue
          case "$ppath" in
            docs/plans/*/*) continue ;;  # archive/deferred destinations
          esac
          pslug=$(basename "$ppath")
          pslug="${pslug%.md}"
          _guard_slug "plan mutation ($TOOL_NAME command)" "$pslug"
        done < <(echo "$CMD" | grep -oE 'docs/plans/[A-Za-z0-9._-]+\.md' | sort -u)
      fi
    fi
  fi
fi

exit 0
