#!/usr/bin/env bash
# migration-drift-check.sh — flag DB-migration drift between repo and target DB
# =============================================================================
#
# WHY THIS EXISTS
#   A code change that also needs a DB migration is ONE atomic unit of work
#   (rules/code-db-atomicity.md). If the code merges but the migration is NOT
#   applied to the target environment, the feature is BROKEN in production
#   while looking "shipped" on master. This script is the automatic FLAG: it
#   compares the migrations present in the repo (HEAD) against the migrations
#   actually applied to the target DB, and surfaces ANY repo migration that is
#   not applied as DRIFT — loudly, where it can't be missed.
#
# GENERIC BY DESIGN (harness-hygiene)
#   This script ships in the harness with NO project identifiers, refs, or
#   secrets. All project-specific bits — which migrations dir, how to read the
#   target DB's applied-migrations list, the prod project ref — are read at
#   runtime from ~/.claude/local/projects.config.json (gitignored, per-machine).
#
# CONFIG (per project, under .projects["<path-or-prefix>"].migration_drift)
#   {
#     "migrations_dir":   "supabase/migrations",   // default
#     "db_check":         "supabase" | "command" | "none",
#     "applied_command":  "<shell cmd printing applied version IDs, one/line>",
#     "supabase_prod_ref":"<project-ref>"           // for db_check=supabase
#   }
#   db_check resolution:
#     - "command":  run applied_command; its stdout (one version-id per line)
#                   IS the applied set. Deterministic; the recommended mode.
#     - "supabase": run `supabase migration list` (optionally --linked with the
#                   prod ref) and parse the REMOTE column. Best-effort.
#     - "none"/absent/undeterminable: result is UNKNOWN (never false-clean).
#
# MODES
#   (default)      human-readable; loud banner on drift.
#   --quiet        machine output: comma-joined drifted version-ids on drift.
#   --json         JSON: {project, migrations_dir, db_check, repo:[], applied:[],
#                          drift:[], status}
#   --project DIR  project root (default: git toplevel of $PWD, else $PWD).
#   --self-test    run the offline self-test suite.
#
# EXIT CODES (the contract the completion-criteria gate + surfacer consume)
#   0  CLEAN    — every repo migration is applied (or repo has none).
#   2  DRIFT    — >=1 repo migration is NOT applied to the target. FLAGGED.
#   3  UNKNOWN  — cannot determine applied set (no config / no DB access / cmd
#                 failed). Treated as a no-op by consumers; never false-blocks.
#   1  USAGE    — bad arguments.
# =============================================================================

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# --- argument parsing -------------------------------------------------------
MODE="human"          # human | quiet | json
PROJECT_ARG=""
DO_SELFTEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q)   MODE="quiet" ;;
    --json)       MODE="json" ;;
    --project|-p) PROJECT_ARG="${2:-}"; shift ;;
    --self-test)  DO_SELFTEST=1 ;;
    -h|--help)
      sed -n '2,52p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "migration-drift-check.sh: unknown argument '$1'" >&2; exit 1 ;;
  esac
  shift
done

# --- helpers ----------------------------------------------------------------

# Normalize a path to a single canonical string form so paths written in any
# of the forms Windows Git Bash produces still compare equal:
#   C:\Users\x  C:/Users/x  /c/Users/x  /cygdrive/c/Users/x  ->  /c/Users/x
# Pure-string (no `cd`/`pwd`) — those are unstable on Windows (jq.exe mangles
# /c/ args to C:/, and `cd` of a C:/ path can remap through the /tmp mount).
_norm_path() {
  local p="${1:-}"
  p="${p//\\//}"                       # backslashes -> forward slashes
  p="${p#/cygdrive}"                   # /cygdrive/c/... -> /c/...
  if [[ "$p" =~ ^([A-Za-z]):/(.*)$ ]]; then   # C:/... -> /c/...
    local d; d="$(printf '%s' "${BASH_REMATCH[1]}" | tr 'A-Z' 'a-z')"
    p="/$d/${BASH_REMATCH[2]}"
  elif [[ "$p" =~ ^([A-Za-z]):$ ]]; then      # bare C: -> /c
    local d; d="$(printf '%s' "${BASH_REMATCH[1]}" | tr 'A-Z' 'a-z')"
    p="/$d"
  fi
  p="${p%/}"                           # strip trailing slash
  echo "$p"
}

# Resolve the project root: explicit arg, else git toplevel, else $PWD.
# Returned in normalized form.
_resolve_project_root() {
  local p="${1:-}"
  if [[ -n "$p" ]]; then _norm_path "$p"; return; fi
  local top
  top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$top" ]]; then _norm_path "$top"; else _norm_path "$PWD"; fi
}

# Expand a leading ~ to $HOME.
_expand_tilde() {
  case "$1" in
    "~")    echo "$HOME" ;;
    "~/"*)  echo "$HOME/${1#\~/}" ;;
    *)      echo "$1" ;;
  esac
}

# Path to the per-machine projects config (override via env for tests).
_projects_config_path() {
  echo "${MIGRATION_DRIFT_PROJECTS_CONFIG:-$HOME/.claude/local/projects.config.json}"
}

# Echo the migration_drift JSON object for $1 (project root). Empty if none.
# Matches a config key by exact path OR by tilde-expanded prefix (longest key
# wins, so a more-specific sub-path config beats a parent).
_project_drift_config() {
  local root="$1" cfg
  cfg="$(_projects_config_path)"
  [[ -f "$cfg" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -e . "$cfg" >/dev/null 2>&1 || return 0

  # Normalize root + each config key to one canonical form (collapse ~, C:\ vs
  # /c/, trailing slashes) so keys written in any path form still match.
  local croot
  croot="$(_norm_path "$root")"

  local keys key canon best="" best_len=0
  keys="$(jq -r '.projects | keys[]?' "$cfg" 2>/dev/null)"
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    canon="$(_norm_path "$(_expand_tilde "$key")")"
    case "$croot" in
      "$canon"|"$canon"/*)
        if [[ ${#canon} -gt $best_len ]]; then best="$key"; best_len=${#canon}; fi
        ;;
    esac
  done <<< "$keys"

  [[ -z "$best" ]] && return 0
  jq -c --arg k "$best" '.projects[$k].migration_drift // empty' "$cfg" 2>/dev/null
}

# Extract the leading numeric version-id from a migration filename.
#   162_business_hours.sql        -> 162
#   0163_add_col.sql              -> 0163
#   20230101120000_foo.sql        -> 20230101120000
_version_of() {
  basename "$1" | grep -oE '^[0-9]+' 2>/dev/null
}

# List repo migration version-ids (sorted, unique), one per line.
_repo_versions() {
  local dir="$1" f v
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*.sql; do
    [[ -e "$f" ]] || continue
    v="$(_version_of "$f")"
    [[ -n "$v" ]] && echo "$v"
  done | sort -u
}

# Parse `supabase migration list` output into the APPLIED (remote) version set.
# A row has columns LOCAL | REMOTE | TIME separated by │ or |. A version-id in
# the REMOTE column means that migration IS applied remotely. Best-effort.
_parse_supabase_applied() {
  # stdin = `supabase migration list` output
  # Normalize box-drawing pipe to ASCII pipe, then take field 2 (REMOTE),
  # extract a leading-or-embedded numeric run.
  sed 's/│/|/g' \
    | awk -F'|' 'NF>=2 {
        r=$2; gsub(/[^0-9]/,"",r);
        if (r != "") print r
      }' \
    | sort -u
}

# Echo applied version-ids (one/line). Returns:
#   0 = produced a definite set (possibly empty)
#   3 = undeterminable (UNKNOWN)
_applied_versions() {
  local cfgjson="$1" db_check applied_cmd ref out rc
  db_check="$(printf '%s' "$cfgjson" | jq -r '.db_check // empty' 2>/dev/null)"
  applied_cmd="$(printf '%s' "$cfgjson" | jq -r '.applied_command // empty' 2>/dev/null)"
  ref="$(printf '%s' "$cfgjson" | jq -r '.supabase_prod_ref // empty' 2>/dev/null)"

  # Auto-resolve db_check when not set: command if applied_command present,
  # else supabase if the CLI exists, else none.
  if [[ -z "$db_check" ]]; then
    if [[ -n "$applied_cmd" ]]; then db_check="command"
    elif command -v supabase >/dev/null 2>&1; then db_check="supabase"
    else db_check="none"; fi
  fi

  case "$db_check" in
    command)
      [[ -z "$applied_cmd" ]] && return 3
      out="$(bash -c "$applied_cmd" 2>/dev/null)"; rc=$?
      [[ $rc -ne 0 ]] && return 3
      # Keep only leading-numeric tokens; tolerate empty (= nothing applied).
      printf '%s\n' "$out" | grep -oE '^[0-9]+' 2>/dev/null | sort -u
      return 0
      ;;
    supabase)
      command -v supabase >/dev/null 2>&1 || return 3
      local args=(migration list)
      if [[ -n "$ref" ]]; then args+=(--linked); fi
      out="$(supabase "${args[@]}" 2>/dev/null)"; rc=$?
      [[ $rc -ne 0 || -z "$out" ]] && return 3
      printf '%s\n' "$out" | _parse_supabase_applied
      return 0
      ;;
    none|*)
      return 3
      ;;
  esac
}

# --- core: compute drift ----------------------------------------------------
# Sets globals: REPO_LIST, APPLIED_LIST, DRIFT_LIST (newline strings),
#               DB_CHECK_USED, STATUS (CLEAN|DRIFT|UNKNOWN), MIG_DIR.
_run_check() {
  local root="$1" cfgjson mig_dir
  cfgjson="$(_project_drift_config "$root")"

  mig_dir="$(printf '%s' "$cfgjson" | jq -r '.migrations_dir // empty' 2>/dev/null)"
  [[ -z "$mig_dir" ]] && mig_dir="supabase/migrations"
  MIG_DIR="$mig_dir"
  local abs_dir="$root/$mig_dir"

  REPO_LIST="$(_repo_versions "$abs_dir")"

  # No repo migrations at all -> nothing can drift -> CLEAN.
  if [[ -z "$REPO_LIST" ]]; then
    APPLIED_LIST=""; DRIFT_LIST=""; STATUS="CLEAN"
    DB_CHECK_USED="$(printf '%s' "$cfgjson" | jq -r '.db_check // "auto"' 2>/dev/null)"
    return 0
  fi

  local applied applied_rc
  applied="$(_applied_versions "$cfgjson")"; applied_rc=$?
  DB_CHECK_USED="$(printf '%s' "$cfgjson" | jq -r '.db_check // "auto"' 2>/dev/null)"

  if [[ $applied_rc -eq 3 ]]; then
    APPLIED_LIST=""; DRIFT_LIST=""; STATUS="UNKNOWN"
    return 0
  fi

  APPLIED_LIST="$applied"
  # DRIFT = repo versions NOT in the applied set.
  DRIFT_LIST="$(comm -23 \
    <(printf '%s\n' "$REPO_LIST" | sort -u) \
    <(printf '%s\n' "$APPLIED_LIST" | sort -u) \
    2>/dev/null | grep -vE '^$' || true)"

  if [[ -n "$DRIFT_LIST" ]]; then STATUS="DRIFT"; else STATUS="CLEAN"; fi
}

# --- output -----------------------------------------------------------------
_emit() {
  local root="$1"
  local drift_csv repo_json applied_json drift_json
  drift_csv="$(printf '%s' "$DRIFT_LIST" | grep -vE '^$' | paste -sd, - 2>/dev/null)"

  case "$MODE" in
    quiet)
      [[ "$STATUS" == "DRIFT" ]] && printf '%s\n' "$drift_csv"
      ;;
    json)
      _json_arr() { printf '%s' "$1" | grep -vE '^$' | jq -R . 2>/dev/null | jq -cs . 2>/dev/null; }
      repo_json="$(_json_arr "$REPO_LIST")";    [[ -z "$repo_json" ]] && repo_json="[]"
      applied_json="$(_json_arr "$APPLIED_LIST")"; [[ -z "$applied_json" ]] && applied_json="[]"
      drift_json="$(_json_arr "$DRIFT_LIST")";   [[ -z "$drift_json" ]] && drift_json="[]"
      jq -nc \
        --arg project "$root" --arg migrations_dir "$MIG_DIR" \
        --arg db_check "$DB_CHECK_USED" --arg status "$STATUS" \
        --argjson repo "$repo_json" --argjson applied "$applied_json" \
        --argjson drift "$drift_json" \
        '{project:$project, migrations_dir:$migrations_dir, db_check:$db_check,
          status:$status, repo:$repo, applied:$applied, drift:$drift}'
      ;;
    human)
      case "$STATUS" in
        DRIFT)
          local n; n="$(printf '%s' "$DRIFT_LIST" | grep -cvE '^$')"
          echo "" >&2
          echo "⚠  MIGRATION DRIFT — code/DB atomicity BROKEN" >&2
          echo "   $n migration(s) on master NOT applied to the target DB:" >&2
          echo "     $drift_csv" >&2
          echo "   Features depending on these migrations are BROKEN / INCOMPLETE." >&2
          echo "   A change is NOT complete until BOTH code is merged AND its" >&2
          echo "   migration is verified applied (rules/code-db-atomicity.md)." >&2
          echo "   Apply the migration to the target env, then re-check." >&2
          echo "" >&2
          ;;
        UNKNOWN)
          echo "[migration-drift] UNKNOWN — could not determine applied migrations for $root" >&2
          echo "[migration-drift] (no projects.config.json migration_drift entry, no DB access," >&2
          echo "[migration-drift]  or the applied-check command failed). Not flagging; configure" >&2
          echo "[migration-drift]  .projects[\"$root\"].migration_drift in ~/.claude/local/projects.config.json." >&2
          ;;
        CLEAN)
          echo "[migration-drift] CLEAN — all repo migrations applied to target ($root)." >&2
          ;;
      esac
      ;;
  esac
}

# --- self-test --------------------------------------------------------------
_self_test() {
  local pass=0 fail=0
  local tmp; tmp="$(mktemp -d 2>/dev/null || mktemp -d -t mdc)"
  local real_home="$HOME"

  _ok()   { echo "PASS  $1"; pass=$((pass+1)); }
  _bad()  { echo "FAIL  $1"; fail=$((fail+1)); }

  # Run the script in a subshell with an isolated HOME + project + config.
  # Returns the exit code; captures stdout into $RUN_OUT.
  RUN_OUT=""
  _run() {
    local proj="$1"; shift
    RUN_OUT="$(HOME="$tmp_home" \
      MIGRATION_DRIFT_PROJECTS_CONFIG="$tmp_home/.claude/local/projects.config.json" \
      bash "${BASH_SOURCE[0]}" --project "$proj" "$@" 2>/dev/null)"
    return $?
  }

  # NOTE: fixtures avoid backslash escapes in applied_command (a raw \n inside a
  # JSON string value is invalid JSON). We point applied_command at a file via
  # `cat`, so the configs are always valid JSON and the applied set is explicit.
  local tmp_home="$tmp/home"
  mkdir -p "$tmp_home/.claude/local"
  local cfg="$tmp_home/.claude/local/projects.config.json"

  # Helper: write a single-project config. $1=proj path, $2=migration_drift JSON.
  _write_cfg() {
    jq -n --arg p "$1" --argjson md "$2" \
      '{version:1, projects: {($p): {migration_drift: $md}}}' > "$cfg"
  }

  # ---- Scenario A: the live 162/163 case ----
  # Repo has 160,161,162,163; target has only 160,161 applied -> DRIFT 162,163.
  local projA="$tmp/projA"
  mkdir -p "$projA/supabase/migrations"
  for v in 160 161 162 163; do echo "-- mig $v" > "$projA/supabase/migrations/${v}_feature.sql"; done
  printf '160\n161\n' > "$tmp/appliedA.txt"
  _write_cfg "$projA" "{\"migrations_dir\":\"supabase/migrations\",\"db_check\":\"command\",\"applied_command\":\"cat $tmp/appliedA.txt\"}"
  _run "$projA" --quiet; rc=$?
  if [[ "$rc" -eq 2 && "$RUN_OUT" == "162,163" ]]; then
    _ok "A: 162/163 drift detected (exit 2, drift='162,163')"
  else
    _bad "A: expected exit 2 + '162,163', got exit $rc out='$RUN_OUT'"
  fi

  # ---- Scenario B: clean (all applied) ----
  printf '160\n161\n162\n163\n' > "$tmp/appliedB.txt"
  _write_cfg "$projA" "{\"db_check\":\"command\",\"applied_command\":\"cat $tmp/appliedB.txt\"}"
  _run "$projA" --quiet; rc=$?
  if [[ "$rc" -eq 0 && -z "$RUN_OUT" ]]; then
    _ok "B: clean (exit 0, no drift output)"
  else
    _bad "B: expected exit 0 + empty, got exit $rc out='$RUN_OUT'"
  fi

  # ---- Scenario C: unknown (no config entry) ----
  echo '{ "version": 1, "projects": {} }' > "$cfg"
  _run "$projA" --quiet; rc=$?
  if [[ "$rc" -eq 3 && -z "$RUN_OUT" ]]; then
    _ok "C: unknown when no migration_drift config (exit 3)"
  else
    _bad "C: expected exit 3 + empty, got exit $rc out='$RUN_OUT'"
  fi

  # ---- Scenario D: repo has no migrations -> clean ----
  local projD="$tmp/projD"; mkdir -p "$projD/supabase/migrations"
  _write_cfg "$projD" '{"db_check":"command","applied_command":"true"}'
  _run "$projD" --quiet; rc=$?
  if [[ "$rc" -eq 0 && -z "$RUN_OUT" ]]; then
    _ok "D: no repo migrations -> clean (exit 0)"
  else
    _bad "D: expected exit 0, got exit $rc out='$RUN_OUT'"
  fi

  # ---- Scenario E: applied_command FAILS -> unknown (never false-clean) ----
  _write_cfg "$projA" '{"db_check":"command","applied_command":"exit 7"}'
  _run "$projA" --quiet; rc=$?
  if [[ "$rc" -eq 3 ]]; then
    _ok "E: failing applied_command -> UNKNOWN, not clean (exit 3)"
  else
    _bad "E: expected exit 3 (unknown), got exit $rc out='$RUN_OUT'"
  fi

  # ---- Scenario F: JSON output shape on drift ----
  _write_cfg "$projA" "{\"db_check\":\"command\",\"applied_command\":\"cat $tmp/appliedA.txt\"}"
  _run "$projA" --json; rc=$?
  local jstatus jdrift
  jstatus="$(printf '%s' "$RUN_OUT" | jq -r '.status' 2>/dev/null)"
  jdrift="$(printf '%s' "$RUN_OUT" | jq -rc '.drift' 2>/dev/null)"
  if [[ "$rc" -eq 2 && "$jstatus" == "DRIFT" && "$jdrift" == '["162","163"]' ]]; then
    _ok "F: --json reports status=DRIFT drift=[\"162\",\"163\"]"
  else
    _bad "F: expected JSON DRIFT [162,163], got exit $rc status='$jstatus' drift='$jdrift'"
  fi

  # ---- Scenario G: prefix key match (config keyed at parent dir) ----
  local projG="$tmp/parent/child"; mkdir -p "$projG/supabase/migrations"
  echo "-- mig 200" > "$projG/supabase/migrations/200_x.sql"
  _write_cfg "$tmp/parent" '{"db_check":"command","applied_command":"true"}'
  _run "$projG" --quiet; rc=$?
  if [[ "$rc" -eq 2 && "$RUN_OUT" == "200" ]]; then
    _ok "G: parent-prefix config key matches child project (drift 200)"
  else
    _bad "G: expected exit 2 + '200', got exit $rc out='$RUN_OUT'"
  fi

  # ---- Scenario H: zero-padded ids treated as distinct strings ----
  local projH="$tmp/projH"; mkdir -p "$projH/supabase/migrations"
  echo "x" > "$projH/supabase/migrations/0042_padded.sql"
  printf '0042\n' > "$tmp/appliedH.txt"
  _write_cfg "$projH" "{\"db_check\":\"command\",\"applied_command\":\"cat $tmp/appliedH.txt\"}"
  _run "$projH" --quiet; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    _ok "H: zero-padded id matches applied (exit 0, clean)"
  else
    _bad "H: expected exit 0, got exit $rc out='$RUN_OUT'"
  fi

  export HOME="$real_home"
  rm -rf "$tmp" 2>/dev/null

  echo ""
  echo "migration-drift-check self-test: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]] && return 0 || return 1
}

# --- dispatch ---------------------------------------------------------------
if [[ "$DO_SELFTEST" -eq 1 ]]; then
  _self_test
  exit $?
fi

ROOT="$(_resolve_project_root "$PROJECT_ARG")"
REPO_LIST=""; APPLIED_LIST=""; DRIFT_LIST=""; STATUS=""; DB_CHECK_USED=""; MIG_DIR=""
_run_check "$ROOT"
_emit "$ROOT"

case "$STATUS" in
  DRIFT)   exit 2 ;;
  UNKNOWN) exit 3 ;;
  *)       exit 0 ;;
esac
