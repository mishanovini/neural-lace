#!/usr/bin/env bash
# migration-drift-surfacer.sh — SessionStart hook (code/DB atomicity FLAG)
# =============================================================================
#
# WHY: a code change that needs a DB migration is ONE atomic unit of work
# (rules/code-db-atomicity.md). If migrations are on master but NOT applied to
# the target DB, the features that depend on them are BROKEN in prod while the
# code looks "shipped." This hook surfaces that drift LOUDLY at session start so
# it can't be missed — the same FLAG the completion-criteria gate consumes.
#
# BEHAVIOR
#   - Resolves the active project (git toplevel of $PWD, else $PWD).
#   - Runs migration-drift-check.sh --quiet for it.
#   - exit 2 (DRIFT)   -> print a loud ⚠ banner naming the unapplied migrations.
#   - exit 0 (CLEAN)   -> silent (no nag).
#   - exit 3 (UNKNOWN) -> silent (no config / no DB access — nothing to flag).
#
# Defensively inert: missing drift script, missing jq, or any error -> silent
# exit 0. A SessionStart hook must never break the session.
#
# Override: MIGRATION_DRIFT_SURFACER_DISABLE=1 silences it.
# Self-test: --self-test (offline; injects a stub drift script).
# =============================================================================

set -uo pipefail

DRIFT_SCRIPT="${MIGRATION_DRIFT_CHECK:-$HOME/.claude/scripts/migration-drift-check.sh}"

_resolve_root() {
  local top
  top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$top" ]]; then echo "$top"; else echo "$PWD"; fi
}

# Run the drift check and surface the result. Echoes the banner to stdout
# (SessionStart hook output becomes session context). Returns the drift rc.
_surface() {
  local root="$1" script="$2"
  [[ "${MIGRATION_DRIFT_SURFACER_DISABLE:-0}" = "1" ]] && return 0
  [[ -f "$script" ]] || return 0

  local csv rc
  csv="$(bash "$script" --quiet --project "$root" 2>/dev/null)"; rc=$?

  if [[ "$rc" -eq 2 && -n "$csv" ]]; then
    local n; n="$(printf '%s' "$csv" | tr ',' '\n' | grep -cvE '^$')"
    echo "[migration-drift] ⚠  $n migration(s) on master NOT applied to prod: $csv"
    echo "[migration-drift]    Features depending on them are BROKEN / INCOMPLETE."
    echo "[migration-drift]    A change needing code + a migration is NOT complete until BOTH"
    echo "[migration-drift]    the code is merged AND the migration is verified applied to the"
    echo "[migration-drift]    target env (rules/code-db-atomicity.md). Apply the migration, or"
    echo "[migration-drift]    treat any feature depending on it as flagged-incomplete."
  fi
  return "$rc"
}

# --- self-test --------------------------------------------------------------
_self_test() {
  local pass=0 fail=0 tmp; tmp="$(mktemp -d 2>/dev/null || mktemp -d -t mds)"
  local proj="$tmp/proj"; mkdir -p "$proj"

  local yes="$tmp/yes.sh" no="$tmp/no.sh" unk="$tmp/unk.sh"
  printf '#!/usr/bin/env bash\necho "162,163"\nexit 2\n' > "$yes"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$no"
  printf '#!/usr/bin/env bash\nexit 3\n' > "$unk"
  chmod +x "$yes" "$no" "$unk" 2>/dev/null

  local out rc
  # DRIFT -> loud banner + rc 2
  out="$(_surface "$proj" "$yes")"; rc=$?
  if [[ "$rc" -eq 2 ]] && printf '%s' "$out" | grep -q '162,163'; then
    echo "PASS  drift surfaces loud banner naming 162,163"; pass=$((pass+1))
  else echo "FAIL  drift banner (rc=$rc out='$out')"; fail=$((fail+1)); fi

  # CLEAN -> silent
  out="$(_surface "$proj" "$no")"; rc=$?
  if [[ "$rc" -eq 0 && -z "$out" ]]; then echo "PASS  clean is silent"; pass=$((pass+1));
  else echo "FAIL  clean not silent (rc=$rc out='$out')"; fail=$((fail+1)); fi

  # UNKNOWN -> silent
  out="$(_surface "$proj" "$unk")"; rc=$?
  if [[ -z "$out" ]]; then echo "PASS  unknown is silent (no nag)"; pass=$((pass+1));
  else echo "FAIL  unknown not silent (out='$out')"; fail=$((fail+1)); fi

  # disable env -> silent
  out="$(MIGRATION_DRIFT_SURFACER_DISABLE=1 _surface "$proj" "$yes")"
  if [[ -z "$out" ]]; then echo "PASS  disable env silences"; pass=$((pass+1));
  else echo "FAIL  disable env not honored (out='$out')"; fail=$((fail+1)); fi

  # missing script -> silent no-op
  out="$(_surface "$proj" "$tmp/nope.sh")"
  if [[ -z "$out" ]]; then echo "PASS  missing drift script -> no-op"; pass=$((pass+1));
  else echo "FAIL  missing script not no-op (out='$out')"; fail=$((fail+1)); fi

  rm -rf "$tmp" 2>/dev/null
  echo ""; echo "migration-drift-surfacer self-test: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]] && return 0 || return 1
}

# --- dispatch ---------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then _self_test; exit $?; fi

ROOT="$(_resolve_root)"
_surface "$ROOT" "$DRIFT_SCRIPT" || true
exit 0
