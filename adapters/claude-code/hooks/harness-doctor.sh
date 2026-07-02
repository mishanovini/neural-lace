#!/bin/bash
# harness-doctor.sh — truth-reconciliation doctor for the NL harness (ADR 058 D4)
#
# WHY THIS EXISTS
# ===============
# The 2026-07-01 effectiveness audit (RC2 "enforcement theater") found that
# claimed enforcement (a hook documented as wired, a rule classified
# "Mechanism") frequently does not actually fire: hooks referenced in
# settings.json that don't exist on disk, hooks whose `lib/`-sourced
# dependency is missing, hooks still pointing at retired legacy paths, and
# drift between the committed template and the live mirror. This doctor is
# the single command that turns "I believe the harness enforces X" into
# "the harness provably enforces X, checked in <2s."
#
# See docs/plans/nl-overhaul-program-2026-07.md task B.1 and
# docs/plans/nl-overhaul-program-2026-07-specs-b.md §B.1 for the full spec
# this file implements.
#
# MODES
# =====
#   --quick (default): checks 1-6 against the LIVE mirror ($HOME/.claude)
#                       and the repo. Never runs self-tests. Fast (<2s
#                       typical). Exit 0 iff zero RED lines.
#   --full            : quick + check 7 (self-test sweep across every live
#                       hook that declares --self-test). Exit 0 iff zero RED.
#   --self-test       : fixture suite in mktemp -d sandboxes
#                       (HARNESS_SELFTEST=1). One RED-producing fixture AND
#                       one GREEN fixture per check class (1-6), plus a
#                       --full fixture exercising check 7 against a stub
#                       hook. Exit 0 iff every scenario behaves as expected.
#
# OUTPUT FORMAT
# =============
#   [doctor] RED <check-id>: <one-line detail>
#   [doctor] WARN <check-id>: <one-line detail>      (non-blocking)
#   [doctor] GREEN — <n> checks passed                (final line, quick/full)
#
# DEPENDENCIES
# ============
# No hard jq dependency — jq is used opportunistically for anything that
# would otherwise need JSON parsing (there is none required for v1's
# checks; settings.json hook-name extraction is done via grep, which is
# adequate for the flat "command": "bash ~/.claude/hooks/<name>.sh" shape
# every hook wiring uses). node is allowed only with graceful absence
# handling; v1 does not require node either. Both are checked defensively
# so a bare-bash environment still runs every check.
#
# CHECKS (v1 — manifest arrives in C.1; v1 embeds its data inline)
# ==================================================================
#   1. wiring-resolves     : every hook basename referenced in live
#                             settings.json AND in the committed template
#                             exists under ~/.claude/hooks/ or
#                             ~/.claude/scripts/ and is readable.
#   2. lib-deps             : for every live hook, each `source`/`.`-included
#                             path under lib/ resolves relative to the
#                             hook's own directory.
#   3. legacy-paths         : no live hook/script references the retired
#                             legacy repo path family (claude-projects/neural…-lace, written split here so the doctor never matches itself).
#   4. template-live-drift  : the sorted basename set of hooks wired in live
#                             settings vs the committed template must match.
#   5. claim-honesty        : embedded v1 checklist — each named hook must
#                             be EITHER wired in live settings OR its rule
#                             file must contain "pending Wave" (the honest-
#                             status marker B.5 adds).
#   6. byte-budget          : total bytes of ~/.claude/rules/*.md vs the
#                             threshold in ~/.claude/local/doctor-budget
#                             (default 1000000 = warn-only era; C.5 lowers
#                             this to 30000). Over budget -> RED if the
#                             threshold file exists and sets a strict value,
#                             else WARN in the default (absent-file) era.
#   7. selftest-sweep       : (--full only) run every live hook containing
#                             the string "--self-test" with
#                             HARNESS_SELFTEST=1 timeout 120
#                             bash <hook> --self-test </dev/null; RED per
#                             non-zero exit.
#
# ESCAPE HATCH
# ============
# None needed — this is a read-only diagnostic tool, not a blocking
# PreToolUse/Stop gate. It is not currently wired into settings.json; it is
# invoked on demand (`harness-doctor.sh --quick`) or by a future Stop/CI
# surface (B.6 wiring reconciliation).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ------------------------------------------------------------
# resolve_repo_root — echoes the repo root, or empty if unresolvable.
# Order: git -C <script dir> rev-parse --show-toplevel > $NL_REPO_ROOT
# ------------------------------------------------------------
resolve_repo_root() {
  local root
  root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  if [[ -n "${NL_REPO_ROOT:-}" ]]; then
    printf '%s\n' "$NL_REPO_ROOT"
    return 0
  fi
  return 1
}

# ------------------------------------------------------------
# resolve_live_home — the live mirror root ($HOME/.claude), overridable
# for self-test sandboxing via HARNESS_DOCTOR_HOME.
# ------------------------------------------------------------
resolve_live_home() {
  if [[ -n "${HARNESS_DOCTOR_HOME:-}" ]]; then
    printf '%s\n' "$HARNESS_DOCTOR_HOME"
    return 0
  fi
  printf '%s\n' "${HOME:-}/.claude"
}

RED_COUNT=0
WARN_COUNT=0
CHECKS_RUN=0

_red() {
  local id="$1" detail="$2"
  echo "[doctor] RED ${id}: ${detail}"
  RED_COUNT=$((RED_COUNT + 1))
}

_warn() {
  local id="$1" detail="$2"
  echo "[doctor] WARN ${id}: ${detail}"
  WARN_COUNT=$((WARN_COUNT + 1))
}

# ------------------------------------------------------------
# extract_wired_hook_basenames <settings-json-path>
# Extracts the set of hook basenames referenced by
# "command": "bash ~/.claude/hooks/<name>.sh" (or scripts/<name>.sh, or
# quoted-path variants with $HOME) lines. Grep-based (no jq dependency) —
# adequate because every hook wiring in this repo uses the flat
# "command": "bash <path>" shape.
# ------------------------------------------------------------
extract_wired_hook_basenames() {
  local settings_file="$1"
  [[ -f "$settings_file" ]] || return 0
  grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*bash[[:space:]]+[^"]*\.claude/(hooks|scripts)/[A-Za-z0-9_.-]+\.sh' "$settings_file" 2>/dev/null \
    | grep -oE '[A-Za-z0-9_.-]+\.sh"?$' \
    | sed 's/"$//' \
    | sort -u
}

# ------------------------------------------------------------
# Check 1: wiring-resolves
# ------------------------------------------------------------
check_wiring_resolves() {
  local live_home="$1" repo_root="$2"
  local live_settings="${live_home}/settings.json"
  local template_settings="${repo_root}/adapters/claude-code/settings.json.template"
  local any_source=0
  local names

  if [[ -f "$live_settings" ]]; then
    any_source=1
    names="$(extract_wired_hook_basenames "$live_settings")"
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      if [[ ! -e "${live_home}/hooks/${name}" && ! -e "${live_home}/scripts/${name}" ]]; then
        _red "wiring-resolves" "live settings.json references '${name}' but it does not exist under ~/.claude/hooks/ or ~/.claude/scripts/"
      elif [[ -e "${live_home}/hooks/${name}" && ! -r "${live_home}/hooks/${name}" ]]; then
        _red "wiring-resolves" "'${name}' exists but is not readable"
      elif [[ -e "${live_home}/scripts/${name}" && ! -r "${live_home}/scripts/${name}" ]]; then
        _red "wiring-resolves" "'${name}' exists but is not readable"
      fi
    done <<< "$names"
  fi

  if [[ -f "$template_settings" ]]; then
    any_source=1
    names="$(extract_wired_hook_basenames "$template_settings")"
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      if [[ ! -e "${repo_root}/adapters/claude-code/hooks/${name}" && ! -e "${repo_root}/adapters/claude-code/scripts/${name}" ]]; then
        _red "wiring-resolves" "template references '${name}' but it does not exist under adapters/claude-code/hooks/ or scripts/"
      fi
    done <<< "$names"
  fi

  if [[ "$any_source" -eq 0 ]]; then
    _warn "wiring-resolves" "no settings.json found (neither live mirror nor template) — nothing to check"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 2: lib-deps
# For every live hook, each `source`/`.`-included path under lib/ must
# resolve relative to the hook's own directory (mirrors how bash resolves
# `source "$(dirname ...)/lib/x.sh"` idioms used across the codebase).
# ------------------------------------------------------------
check_lib_deps() {
  local live_home="$1"
  local hooks_dir="${live_home}/hooks"
  [[ -d "$hooks_dir" ]] || { _warn "lib-deps" "no live hooks directory at ${hooks_dir} — nothing to check"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local hook
  for hook in "$hooks_dir"/*.sh; do
    [[ -f "$hook" ]] || continue
    local hook_dir
    hook_dir="$(cd "$(dirname "$hook")" && pwd)"
    # Match any line containing a source/. include directive, then extract
    # only the "lib/<name>.sh" tail so we don't false-positive on sourcing
    # unrelated files (e.g. .env files). The line-level filter tolerates
    # nested command substitutions like "$(dirname "${BASH_SOURCE[0]}")/lib/x.sh"
    # that a single quote-aware regex can't span.
    # process-substitution (not a trailing pipe) so the while-loop body runs
    # in THIS shell, not a subshell — otherwise _red's RED_COUNT increment
    # would be invisible to the caller.
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      if [[ ! -f "${hook_dir}/${rel}" ]]; then
        _red "lib-deps" "$(basename "$hook") sources '${rel}' but ${hook_dir}/${rel} does not exist"
      fi
    done < <(grep -E '(^|[^A-Za-z_])(source|\.)[[:space:]]+["'"'"']?.*lib/[A-Za-z0-9_.-]+\.sh' "$hook" 2>/dev/null \
      | grep -oE 'lib/[A-Za-z0-9_.-]+\.sh' \
      | sort -u)
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 3: legacy-paths
# ------------------------------------------------------------
check_legacy_paths() {
  local live_home="$1"
  local hooks_dir="${live_home}/hooks"
  local scripts_dir="${live_home}/scripts"
  local found=0
  # Pattern built by concatenation so this script's own text never matches it
  # (the doctor must not RED-flag itself; see Wave-B integration note).
  local legacy_pat="claude-projects/neural""-lace"

  if [[ -d "$hooks_dir" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      _red "legacy-paths" "${f} references the retired legacy repo path (${legacy_pat})"
      found=1
    done < <(grep -rl "$legacy_pat" "$hooks_dir" 2>/dev/null)
  fi
  if [[ -d "$scripts_dir" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      _red "legacy-paths" "${f} references the retired legacy repo path (${legacy_pat})"
      found=1
    done < <(grep -rl "$legacy_pat" "$scripts_dir" 2>/dev/null)
  fi
  if [[ ! -d "$hooks_dir" && ! -d "$scripts_dir" ]]; then
    _warn "legacy-paths" "no live hooks/ or scripts/ directory — nothing to check"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 4: template-live-drift
# ------------------------------------------------------------
check_template_live_drift() {
  local live_home="$1" repo_root="$2"
  local live_settings="${live_home}/settings.json"
  local template_settings="${repo_root}/adapters/claude-code/settings.json.template"

  if [[ ! -f "$live_settings" || ! -f "$template_settings" ]]; then
    _warn "template-live-drift" "cannot compare — live settings.json or template missing"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local live_names template_names
  live_names="$(extract_wired_hook_basenames "$live_settings")"
  template_names="$(extract_wired_hook_basenames "$template_settings")"

  local live_only template_only
  live_only="$(comm -23 <(printf '%s\n' "$live_names" | grep -v '^$' | sort -u) <(printf '%s\n' "$template_names" | grep -v '^$' | sort -u))"
  template_only="$(comm -13 <(printf '%s\n' "$live_names" | grep -v '^$' | sort -u) <(printf '%s\n' "$template_names" | grep -v '^$' | sort -u))"

  if [[ -n "$live_only" ]]; then
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      _red "template-live-drift" "'${n}' is wired in live settings.json but not in the committed template"
    done <<< "$live_only"
  fi
  if [[ -n "$template_only" ]]; then
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      _red "template-live-drift" "'${n}' is wired in the committed template but not in live settings.json"
    done <<< "$template_only"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 5: claim-honesty
# Embedded v1 checklist. Each hook must EITHER be wired in live settings.json
# OR its rule file must contain the honest-status marker string "pending Wave".
# ------------------------------------------------------------
CLAIM_HONESTY_HOOKS=(
  "customer-facing-review-gate.sh:rules/customer-facing-review.md"
  "worktree-teardown-gate.sh:rules/worktree-isolation.md"
  "session-start-worktree-advisor.sh:rules/worktree-isolation.md"
  "stalled-work-surfacer.sh:rules/background-work-tracking.md"
  "workstreams-turn-emit.sh:rules/workstreams-state.md"
)

check_claim_honesty() {
  local live_home="$1" repo_root="$2"
  local live_settings="${live_home}/settings.json"
  local live_names=""
  [[ -f "$live_settings" ]] && live_names="$(extract_wired_hook_basenames "$live_settings")"

  local entry hook_name rule_rel
  for entry in "${CLAIM_HONESTY_HOOKS[@]}"; do
    hook_name="${entry%%:*}"
    rule_rel="${entry#*:}"
    if printf '%s\n' "$live_names" | grep -qx "$hook_name"; then
      continue
    fi
    local rule_path="${repo_root}/adapters/claude-code/${rule_rel}"
    if [[ -f "$rule_path" ]] && grep -q "pending Wave" "$rule_path" 2>/dev/null; then
      continue
    fi
    _red "claim-honesty" "${hook_name} is not wired in live settings.json AND its rule (${rule_rel}) lacks the 'pending Wave' honest-status marker"
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 6: byte-budget
# ------------------------------------------------------------
check_byte_budget() {
  local live_home="$1"
  local rules_dir="${live_home}/rules"
  local budget_file="${live_home}/local/doctor-budget"
  local default_budget=1000000
  local budget="$default_budget"
  local strict=0

  if [[ -f "$budget_file" ]]; then
    local v
    v="$(tr -d '[:space:]' < "$budget_file" 2>/dev/null)"
    if [[ "$v" =~ ^[0-9]+$ ]]; then
      budget="$v"
      strict=1
    fi
  fi

  if [[ ! -d "$rules_dir" ]]; then
    _warn "byte-budget" "no live rules/ directory at ${rules_dir} — nothing to check"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local total
  total="$(cat "$rules_dir"/*.md 2>/dev/null | wc -c | tr -d '[:space:]')"
  total="${total:-0}"

  if [[ "$total" -gt "$budget" ]]; then
    if [[ "$strict" -eq 1 ]]; then
      _red "byte-budget" "${total} bytes across ~/.claude/rules/*.md exceeds the configured budget of ${budget}"
    else
      _warn "byte-budget" "${total} bytes across ~/.claude/rules/*.md exceeds the default warn-only budget of ${budget} (set ~/.claude/local/doctor-budget to make this strict)"
    fi
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 7: selftest-sweep (--full only)
# ------------------------------------------------------------
check_selftest_sweep() {
  local live_home="$1"
  local hooks_dir="${live_home}/hooks"
  [[ -d "$hooks_dir" ]] || { _warn "selftest-sweep" "no live hooks directory — nothing to check"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local hook
  for hook in "$hooks_dir"/*.sh; do
    [[ -f "$hook" ]] || continue
    grep -q -- '--self-test' "$hook" 2>/dev/null || continue
    local out rc
    out="$(HARNESS_SELFTEST=1 timeout 120 bash "$hook" --self-test </dev/null 2>&1)"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      local last_line
      last_line="$(printf '%s\n' "$out" | tail -n 1)"
      _red "selftest-sweep" "$(basename "$hook") --self-test exited ${rc}: ${last_line}"
    fi
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# run_quick_checks — checks 1-6 against the given live_home/repo_root
# ------------------------------------------------------------
run_quick_checks() {
  local live_home="$1" repo_root="$2"
  check_wiring_resolves "$live_home" "$repo_root"
  check_lib_deps "$live_home"
  check_legacy_paths "$live_home"
  check_template_live_drift "$live_home" "$repo_root"
  check_claim_honesty "$live_home" "$repo_root"
  check_byte_budget "$live_home"
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
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t harness-doctor)
  if [[ -z "$TMPROOT" ]] || [[ ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  # Helper: build a minimal fake "live home" + "repo root" pair and return
  # the exit code of a --quick invocation against them.
  #   $1 = scenario label
  #   $2 = "live" | "repo" | "both"  -> which fixture builder(s) to call
  # The scenario functions below populate $LIVE and $REPO directly.
  _scenario_dir() {
    local label="$1"
    local dir="$TMPROOT/$label"
    mkdir -p "$dir/live/hooks" "$dir/live/rules" "$dir/live/scripts" "$dir/live/local"
    mkdir -p "$dir/repo/adapters/claude-code/hooks" "$dir/repo/adapters/claude-code/scripts" "$dir/repo/adapters/claude-code/rules"
    printf '%s\n' "$dir"
  }

  _write_settings() {
    local path="$1"; shift
    local body='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":['
    local first=1
    local name
    for name in "$@"; do
      if [[ "$first" -eq 0 ]]; then body="${body},"; fi
      first=0
      body="${body}{\"type\":\"command\",\"command\":\"bash ~/.claude/hooks/${name}\"}"
    done
    body="${body}]}]}}"
    printf '%s' "$body" > "$path"
  }

  # Every scenario except the dedicated check-5 (claim-honesty) ones needs
  # the claim-honesty checklist satisfied so unrelated scenarios don't
  # spuriously RED on check 5. Stamp the "pending Wave" marker into each
  # checklist rule file.
  _stamp_claim_honesty_green() {
    local dir="$1"
    mkdir -p "$dir/repo/adapters/claude-code/rules"
    local rel
    for rel in "rules/customer-facing-review.md" "rules/worktree-isolation.md" "rules/background-work-tracking.md" "rules/workstreams-state.md"; do
      echo "pending Wave D" > "$dir/repo/adapters/claude-code/${rel}"
    done
  }

  _run_quick() {
    local dir="$1"
    HARNESS_DOCTOR_HOME="$dir/live" NL_REPO_ROOT="$dir/repo" bash "$SELF_TEST_HOOK" --quick "$dir/repo" 2>&1
  }

  _assert() {
    local label="$1" want_rc="$2" got_rc="$3" grep_pattern="${4:-}" output="${5:-}"
    local ok=1
    if [[ "$got_rc" != "$want_rc" ]]; then ok=0; fi
    if [[ -n "$grep_pattern" ]] && ! printf '%s' "$output" | grep -q "$grep_pattern"; then ok=0; fi
    if [[ "$ok" -eq 1 ]]; then
      echo "self-test (${label}): PASS" >&2
      PASSED=$((PASSED + 1))
    else
      echo "self-test (${label}): FAIL (rc=${got_rc}, expected ${want_rc}, pattern='${grep_pattern}')" >&2
      echo "--- output ---" >&2
      printf '%s\n' "$output" >&2
      FAILED=$((FAILED + 1))
    fi
  }

  # ---- Check 1 (wiring-resolves): RED fixture — settings references a
  # missing hook ----
  D=$(_scenario_dir c1-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/does-not-exist.sh"}]}]}}
EOF
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "1-wiring-resolves-red" 1 "$RC" "RED wiring-resolves" "$OUT"

  # ---- Check 1: GREEN fixture — the referenced hook exists ----
  D=$(_scenario_dir c1-green)
  _stamp_claim_honesty_green "$D"
  echo '#!/bin/bash' > "$D/live/hooks/present.sh"
  chmod +x "$D/live/hooks/present.sh"
  cat > "$D/live/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/present.sh"}]}]}}
EOF
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/present.sh" "$D/repo/adapters/claude-code/hooks/present.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "1-wiring-resolves-green" 0 "$RC" "" "$OUT"

  # ---- Check 2 (lib-deps): RED fixture — hook sources a missing lib file ----
  D=$(_scenario_dir c2-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/uses-lib.sh" <<'EOF'
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/missing-lib.sh"
EOF
  chmod +x "$D/live/hooks/uses-lib.sh"
  _write_settings "$D/live/settings.json" "uses-lib.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/uses-lib.sh" "$D/repo/adapters/claude-code/hooks/uses-lib.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "2-lib-deps-red" 1 "$RC" "RED lib-deps" "$OUT"

  # ---- Check 2: GREEN fixture — the sourced lib file exists ----
  D=$(_scenario_dir c2-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/hooks/lib"
  echo '#!/bin/bash' > "$D/live/hooks/lib/present-lib.sh"
  cat > "$D/live/hooks/uses-lib-ok.sh" <<'EOF'
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/present-lib.sh"
EOF
  chmod +x "$D/live/hooks/uses-lib-ok.sh"
  _write_settings "$D/live/settings.json" "uses-lib-ok.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/uses-lib-ok.sh" "$D/repo/adapters/claude-code/hooks/uses-lib-ok.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "2-lib-deps-green" 0 "$RC" "" "$OUT"

  # ---- Check 3 (legacy-paths): RED fixture — a hook references the
  # retired path family ----
  D=$(_scenario_dir c3-red)
  _stamp_claim_honesty_green "$D"
  {
    printf '%s\n' '#!/bin/bash'
    printf 'SRC="$HOME/claude-projects/neural%s"\n' '-lace/adapters/claude-code'
  } > "$D/live/hooks/legacy.sh"
  chmod +x "$D/live/hooks/legacy.sh"
  _write_settings "$D/live/settings.json" "legacy.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/legacy.sh" "$D/repo/adapters/claude-code/hooks/legacy.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "3-legacy-paths-red" 1 "$RC" "RED legacy-paths" "$OUT"

  # ---- Check 3: GREEN fixture — no legacy references ----
  D=$(_scenario_dir c3-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/modern.sh" <<'EOF'
#!/bin/bash
echo "clean"
EOF
  chmod +x "$D/live/hooks/modern.sh"
  _write_settings "$D/live/settings.json" "modern.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/modern.sh" "$D/repo/adapters/claude-code/hooks/modern.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "3-legacy-paths-green" 0 "$RC" "" "$OUT"

  # ---- Check 4 (template-live-drift): RED fixture — live and template
  # wire different hook sets ----
  D=$(_scenario_dir c4-red)
  _stamp_claim_honesty_green "$D"
  echo '#!/bin/bash' > "$D/live/hooks/only-live.sh"
  echo '#!/bin/bash' > "$D/repo/adapters/claude-code/hooks/only-template.sh"
  _write_settings "$D/live/settings.json" "only-live.sh"
  _write_settings "$D/repo/adapters/claude-code/settings.json.template" "only-template.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "4-template-live-drift-red" 1 "$RC" "RED template-live-drift" "$OUT"

  # ---- Check 4: GREEN fixture — identical wired sets ----
  D=$(_scenario_dir c4-green)
  _stamp_claim_honesty_green "$D"
  echo '#!/bin/bash' > "$D/live/hooks/shared.sh"
  echo '#!/bin/bash' > "$D/repo/adapters/claude-code/hooks/shared.sh"
  _write_settings "$D/live/settings.json" "shared.sh"
  _write_settings "$D/repo/adapters/claude-code/settings.json.template" "shared.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "4-template-live-drift-green" 0 "$RC" "" "$OUT"

  # ---- Check 5 (claim-honesty): RED fixture — a checklist hook is neither
  # wired nor honestly marked pending ----
  D=$(_scenario_dir c5-red)
  mkdir -p "$D/repo/adapters/claude-code/rules"
  cat > "$D/repo/adapters/claude-code/rules/worktree-isolation.md" <<'EOF'
# Worktree Isolation
No pending marker here.
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "5-claim-honesty-red" 1 "$RC" "RED claim-honesty" "$OUT"

  # ---- Check 5: GREEN fixture — the same hook is honestly marked pending ----
  D=$(_scenario_dir c5-green)
  mkdir -p "$D/repo/adapters/claude-code/rules"
  cat > "$D/repo/adapters/claude-code/rules/worktree-isolation.md" <<'EOF'
# Worktree Isolation
Status: pending Wave D — not yet wired.
EOF
  cat > "$D/repo/adapters/claude-code/rules/background-work-tracking.md" <<'EOF'
pending Wave D
EOF
  cat > "$D/repo/adapters/claude-code/rules/workstreams-state.md" <<'EOF'
pending Wave D
EOF
  cat > "$D/repo/adapters/claude-code/rules/customer-facing-review.md" <<'EOF'
pending Wave D
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "5-claim-honesty-green" 0 "$RC" "" "$OUT"

  # ---- Check 6 (byte-budget): RED fixture — strict budget exceeded ----
  D=$(_scenario_dir c6-red)
  _stamp_claim_honesty_green "$D"
  head -c 200 /dev/zero | tr '\0' 'x' > "$D/live/rules/big.md"
  echo "100" > "$D/live/local/doctor-budget"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "6-byte-budget-red" 1 "$RC" "RED byte-budget" "$OUT"

  # ---- Check 6: GREEN fixture — under budget ----
  D=$(_scenario_dir c6-green)
  _stamp_claim_honesty_green "$D"
  echo "small" > "$D/live/rules/small.md"
  echo "1000000" > "$D/live/local/doctor-budget"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "6-byte-budget-green" 0 "$RC" "" "$OUT"

  # ---- Check 7 (--full only): RED fixture — a stub hook's --self-test fails ----
  D=$(_scenario_dir c7-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/failing.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then
  echo "self-test: intentional failure" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$D/live/hooks/failing.sh"
  _write_settings "$D/live/settings.json" "failing.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/failing.sh" "$D/repo/adapters/claude-code/hooks/failing.sh"
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" bash "$SELF_TEST_HOOK" --full "$D/repo" 2>&1)"; RC=$?
  _assert "7-selftest-sweep-red" 1 "$RC" "RED selftest-sweep" "$OUT"

  # ---- Check 7: GREEN fixture — a stub hook's --self-test passes ----
  D=$(_scenario_dir c7-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/passing.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then
  echo "self-test: ok"
  exit 0
fi
exit 0
EOF
  chmod +x "$D/live/hooks/passing.sh"
  _write_settings "$D/live/settings.json" "passing.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/passing.sh" "$D/repo/adapters/claude-code/hooks/passing.sh"
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" bash "$SELF_TEST_HOOK" --full "$D/repo" 2>&1)"; RC=$?
  _assert "7-selftest-sweep-green" 0 "$RC" "" "$OUT"

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed" >&2
  if [[ "$FAILED" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi

# ============================================================
# Normal (non-self-test) invocation
# ============================================================
MODE="${1:-quick}"
case "$MODE" in
  --quick|quick) MODE="quick" ;;
  --full|full) MODE="full" ;;
  *) MODE="quick" ;;
esac

# Second positional arg (self-test-only usage) lets the self-test harness
# pass an explicit repo root without relying on git in the sandbox.
EXPLICIT_REPO_ROOT="${2:-}"

LIVE_HOME="$(resolve_live_home)"
if [[ -n "$EXPLICIT_REPO_ROOT" ]]; then
  REPO_ROOT="$EXPLICIT_REPO_ROOT"
else
  REPO_ROOT="$(resolve_repo_root)"
fi

if [[ -z "${REPO_ROOT:-}" ]]; then
  echo "[doctor] WARN repo-root: could not resolve repo root (git unavailable and NL_REPO_ROOT unset) — repo-relative checks will warn"
fi

run_quick_checks "$LIVE_HOME" "$REPO_ROOT"

if [[ "$MODE" == "full" ]]; then
  check_selftest_sweep "$LIVE_HOME"
fi

if [[ "$RED_COUNT" -eq 0 ]]; then
  echo "[doctor] GREEN — ${CHECKS_RUN} checks passed"
  exit 0
else
  echo "[doctor] FAILED — ${RED_COUNT} red, ${WARN_COUNT} warn, ${CHECKS_RUN} checks run"
  exit 1
fi
