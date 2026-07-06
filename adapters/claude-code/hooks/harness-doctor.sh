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
#   --quick (default): checks 1-7 against the LIVE mirror ($HOME/.claude)
#                       and the repo. Never runs self-tests. Fast (<2s
#                       typical). Exit 0 iff zero RED lines.
#   --full            : quick + check 8 (self-test sweep across every live
#                       hook that declares --self-test). Exit 0 iff zero RED.
#   --self-test       : fixture suite in mktemp -d sandboxes
#                       (HARNESS_SELFTEST=1). One RED-producing fixture AND
#                       one GREEN fixture per check class (1-7), plus a
#                       --full fixture exercising check 8 against a stub
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
# CHECKS (v2 — manifest-driven as of C.1; adapters/claude-code/manifest.json)
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
#   5. claim-honesty        : manifest-driven (replaced the embedded v1
#                             checklist in C.1) — every `kind: gate` entry
#                             in manifest.json must EITHER declare
#                             wired_template true AND have all its hooks[]
#                             present in live settings.json, OR carry a
#                             non-empty honest_status string naming how it
#                             actually fires. WARN (skip) when no
#                             manifest.json exists (pre-C.1 machine) or no
#                             JSON parser (node/jq) is available.
#   6. byte-budget          : total bytes of ~/.claude/rules/*.md vs the
#                             threshold in ~/.claude/local/doctor-budget
#                             (default 1000000 = warn-only era; C.5 lowers
#                             this to 30000). Over budget -> RED if the
#                             threshold file exists and sets a strict value,
#                             else WARN in the default (absent-file) era.
#   7. manifest-check       : when a repo manifest.json exists, invoke
#                             scripts/manifest-check.sh check (schema
#                             validation + hooks<->disk coverage both ways +
#                             wired_template truth vs the template +
#                             doctrine_file existence + gate honest_status).
#                             Non-zero exit -> RED. WARN (skip, graceful)
#                             when the manifest is absent (pre-C.1 machine)
#                             or the checker script cannot be found.
#   8. selftest-sweep       : (--full only) run every live hook containing
#                             the string "--self-test" with
#                             HARNESS_SELFTEST=1 timeout 1500
#                             bash <hook> --self-test </dev/null; RED per
#                             non-zero exit.
#
# WAVE F BUDGET CHECKS (task F.1, specs-f §F.1 — all in --quick)
# ===============================================================
#   budget-chains           : Stop <= 6, SessionStart <= 8 total hook
#                             entries, checked against BOTH the live
#                             settings.json and the committed template.
#   budget-blocking-gates   : manifest entries with blocking:true <= 12.
#   budget-always-loaded    : byte-sum of ~/.claude/rules/*.md +
#                             ~/.claude/CLAUDE.md <= 30000 (dedicated,
#                             non-configurable — distinct from the older
#                             configurable check_byte_budget/rules-only
#                             mechanism, which stays as-is).
#   budget-active-plans     : `Status: ACTIVE` plans <= 3 machine-wide,
#                             walking the exact root list documented at
#                             _budget_active_plans_roots()'s header
#                             comment; fail-open (WARN) per unreadable
#                             root, count what is readable.
#   budget-worktrees-branches: git worktree count <= 6, none >7d without
#                             a commit; local branches with no upstream
#                             and no commit in 7d flagged.
#   new-gate-evidence-bar   : manifest entries with added_after >=
#                             "2026-07" must carry golden_scenario,
#                             fp_expectation, retirement_condition, and
#                             (waiver_path OR honesty_rationale) —
#                             ADR 059 D4. Doctor-side half only; the
#                             constitution §10 prose half is
#                             orchestrator-owned.
#
# Staleness ESCALATION (deferral/removal proposals) is NOT here — it
# lives in session-start-digest.sh (a SessionStart feed), per specs-f
# §F.1: "the doctor only REDs on budget breach; the digest carries the
# remediation proposals."
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
  # Config-file tier (written by install.sh; same anchor nl-paths.sh uses) —
  # the live mirror is not a git repo, so this is the tier that fires there.
  local cfg="${HOME:-}/.claude/local/nl-repo-path"
  if [[ -f "$cfg" ]]; then
    root="$(head -1 "$cfg" | tr -d '\r\n')"
    if [[ -n "$root" && -d "$root" ]]; then
      printf '%s\n' "$root"
      return 0
    fi
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
    # Skip this scanner itself — its self-test section embeds fixture
    # source-lines (lib/missing-lib.sh etc.) that are data, not includes.
    [[ "$(basename "$hook")" == "harness-doctor.sh" ]] && continue
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
# resolve_manifest <live_home> <repo_root>
# Echoes the manifest path (live-first, repo fallback) or nothing.
# ------------------------------------------------------------
resolve_manifest() {
  local live_home="$1" repo_root="$2"
  if [[ -f "${live_home}/manifest.json" ]]; then
    printf '%s\n' "${live_home}/manifest.json"
    return 0
  fi
  if [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/manifest.json" ]]; then
    printf '%s\n' "${repo_root}/adapters/claude-code/manifest.json"
    return 0
  fi
  return 1
}

# ------------------------------------------------------------
# extract_manifest_gates <manifest>
# Emits a normalized stream for check 5:
#   GATE|<id>|<wired01>|<honest01>
#   GH|<id>|<hook-basename>
# node preferred, jq fallback; caller handles the neither-case.
# ------------------------------------------------------------
extract_manifest_gates() {
  local manifest="$1"
  if command -v node >/dev/null 2>&1; then
    node -e '
const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
for (const e of m.entries || []) {
  if (e.kind !== "gate") continue;
  const honest = (typeof e.honest_status === "string" && e.honest_status.trim().length > 0) ? "1" : "0";
  console.log(["GATE", e.id, e.wired_template ? "1" : "0", honest].join("|"));
  for (const h of e.hooks || []) console.log(["GH", e.id, h].join("|"));
}' "$manifest" 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then
    jq -r '
.entries[] | select(.kind == "gate") as $e |
(["GATE", $e.id,
  (if $e.wired_template then "1" else "0" end),
  (if (($e.honest_status // "") | length) > 0 then "1" else "0" end)] | join("|")),
((($e.hooks // [])[]) | "GH|\($e.id)|\(.)")' "$manifest" 2>/dev/null
  fi
}

# ------------------------------------------------------------
# Check 5: claim-honesty (manifest-driven, C.1)
# Every `kind: gate` entry in manifest.json must EITHER be wired_template
# true with all its hooks present in live settings.json, OR carry a
# non-empty honest_status. Graceful WARN when no manifest / no parser.
# ------------------------------------------------------------
check_claim_honesty() {
  local live_home="$1" repo_root="$2"
  local manifest
  if ! manifest="$(resolve_manifest "$live_home" "$repo_root")"; then
    _warn "claim-honesty" "no manifest.json found (live mirror or repo) — manifest-driven claim-honesty skipped (pre-C.1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "claim-honesty" "neither node nor jq available — manifest-driven claim-honesty skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local stream
  stream="$(extract_manifest_gates "$manifest")"
  if [[ -z "$stream" ]]; then
    _warn "claim-honesty" "manifest at ${manifest} yielded no gate entries (parse failure or none declared)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local live_settings="${live_home}/settings.json"
  local live_missing=0
  if [[ ! -f "$live_settings" ]]; then
    live_missing=1
    _warn "claim-honesty" "live settings.json missing — live-wiring verification for wired gates skipped"
  fi

  local tag id wired honest t2 i2 hook
  while IFS='|' read -r tag id wired honest; do
    [[ "$tag" == "GATE" ]] || continue
    if [[ "$honest" == "1" ]]; then
      continue
    fi
    if [[ "$wired" == "0" ]]; then
      _red "claim-honesty" "manifest gate '${id}' has wired_template false and no honest_status — name how it fires or which Wave lands its wiring"
      continue
    fi
    [[ "$live_missing" -eq 1 ]] && continue
    while IFS='|' read -r t2 i2 hook; do
      [[ "$t2" == "GH" && "$i2" == "$id" ]] || continue
      if ! grep -qF "$hook" "$live_settings" 2>/dev/null; then
        _red "claim-honesty" "manifest gate '${id}' claims wired_template true but hook '${hook}' does not appear in live settings.json — run install"
      fi
    done <<< "$stream"
  done <<< "$stream"
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 7: manifest-check
# When a repo manifest exists, run scripts/manifest-check.sh check against
# the repo. Graceful WARN when the manifest is absent (pre-C.1 machine),
# the repo root is unresolved, or the checker script cannot be found.
# ------------------------------------------------------------
check_manifest() {
  local live_home="$1" repo_root="$2"
  local repo_manifest=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/manifest.json" ]] \
    && repo_manifest="${repo_root}/adapters/claude-code/manifest.json"

  if [[ -z "$repo_manifest" ]]; then
    if [[ -f "${live_home}/manifest.json" ]]; then
      _warn "manifest-check" "manifest present in live mirror but no repo manifest resolved — manifest-check needs the repo (hooks/ coverage); skipped"
    else
      _warn "manifest-check" "no manifest.json found — manifest-check skipped (pre-C.1 machine)"
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local checker="${repo_root}/adapters/claude-code/scripts/manifest-check.sh"
  [[ -f "$checker" ]] || checker="${live_home}/scripts/manifest-check.sh"
  if [[ ! -f "$checker" ]]; then
    _warn "manifest-check" "manifest.json present but manifest-check.sh not found (repo scripts/ or live scripts/) — cannot validate"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out rc n
  out="$(MANIFEST_CHECK_ROOT="$repo_root" bash "$checker" check 2>&1)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    n="$(printf '%s\n' "$out" | grep -c 'RED' 2>/dev/null || true)"
    _red "manifest-check" "manifest-check reported ${n:-?} RED finding(s) — run: bash adapters/claude-code/scripts/manifest-check.sh"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# _hash_file <path> — best-effort content hash (sha1sum -> shasum ->
# openssl -> byte-count fallback). Mirrors install.sh's _hash_path (item
# 4's copy-then-verify backup) so both sides of the NL-FINDING-017 fix
# use the same hashing discipline.
# ------------------------------------------------------------
_hash_file() {
  local p="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "$p" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum "$p" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl sha1 "$p" 2>/dev/null | awk '{print $NF}'
  else
    wc -c < "$p" 2>/dev/null | tr -d '[:space:]'
  fi
}

# ------------------------------------------------------------
# Check: manifest-freshness (NL-FINDING-017, specs-e §E.10 item 4)
# Live ~/.claude/manifest.json hash vs the repo's manifest.json hash. A
# mismatch means install.sh has not been run since the repo manifest
# last changed (the exact D.5 cutover failure: install.sh aborted
# mid-run, live manifest.json stayed at its stale pre-cutover state, and
# the doctor's OTHER checks then reported 20 claim-honesty REDs against
# retired-gate entries that no longer existed on master — the true
# defect was manifest STALENESS, not the gates themselves). RED with an
# honest "run install" remediation; graceful WARN when either side is
# absent (pre-C.1 machine, or repo manifest not resolved).
# ------------------------------------------------------------
check_manifest_freshness() {
  local live_home="$1" repo_root="$2"
  local live_manifest="${live_home}/manifest.json"
  local repo_manifest=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/manifest.json" ]] \
    && repo_manifest="${repo_root}/adapters/claude-code/manifest.json"

  if [[ ! -f "$live_manifest" || -z "$repo_manifest" ]]; then
    _warn "manifest-freshness" "cannot compare — live manifest.json (${live_manifest}) or repo manifest.json missing (pre-C.1 machine or unresolved repo root)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local live_hash repo_hash
  live_hash="$(_hash_file "$live_manifest")"
  repo_hash="$(_hash_file "$repo_manifest")"
  if [[ -z "$live_hash" || -z "$repo_hash" ]]; then
    _warn "manifest-freshness" "could not hash one or both manifests (live=${live_manifest}, repo=${repo_manifest}) — no hashing tool available"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  if [[ "$live_hash" != "$repo_hash" ]]; then
    _red "manifest-freshness" "live ~/.claude/manifest.json (hash ${live_hash:0:12}) does not match repo adapters/claude-code/manifest.json (hash ${repo_hash:0:12}) — run: bash adapters/claude-code/install.sh"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: wave-e-surfaces (specs-e §E.10 item 12) — doctor predicates from
# the E.1/E.7/E.8/E.9 fragments, implemented VERBATIM per
# adapters/claude-code/tests/fixtures/wave-e/{E.1,E.7,E.8,E.9}/doctor-predicate.md.
# E.5/E.6 fragments are being built in PARALLEL (batch 2) and are being
# built by the orchestrator at integration per specs-e §E.10 item 12 —
# they are SKIPPED here (noted, not implemented) because their fragments
# do not exist on this builder's tree.
# ------------------------------------------------------------
check_wave_e_surfaces() {
  local live_home="$1" repo_root="$2"

  # --- E.1: session-start-digest.sh (predicates 1, 2, 4; predicate 3 is a
  # one-time point-in-time check per the fragment, not a recurring gate). ---
  local e1_hook="${live_home}/hooks/session-start-digest.sh"
  if [[ ! -f "$e1_hook" ]]; then
    _warn "wave-e-e1-digest" "session-start-digest.sh missing from live mirror at ${e1_hook} — E.1 not yet installed on this machine"
  else
    if ! bash "$e1_hook" --self-test >/dev/null 2>&1; then
      _red "wave-e-e1-digest" "session-start-digest.sh --self-test exited non-zero at ${e1_hook}"
    fi
  fi
  local e1_probe_guard="${repo_root}/adapters/claude-code/attic/principles-compliance-gate.sh"
  if [[ -n "$repo_root" && -f "$e1_probe_guard" ]]; then
    if ! grep -q 'NL-FINDING-021' "$e1_probe_guard" 2>/dev/null || ! grep -q 'ALERT_ANOMALY_COUNT' "$e1_probe_guard" 2>/dev/null; then
      _red "wave-e-e1-digest" "NL-FINDING-021 probe guard missing from ${e1_probe_guard} (anomaly-count/health check before the alert write)"
    fi
  fi

  # --- E.7: session-resumer.sh (Check A always; Check B Windows-only /
  # --full-style honest warn, per the fragment's "Why WARN not RED"). ---
  local e7_script="${live_home}/scripts/session-resumer.sh"
  if [[ ! -f "$e7_script" ]]; then
    _warn "session-resumer" "session-resumer.sh missing from live mirror at ${e7_script} — E.7 not yet installed on this machine"
  else
    if [[ ! -x "$e7_script" ]]; then
      _red "session-resumer" "session-resumer.sh missing or not executable at ${e7_script}"
    elif ! grep -q -- '--self-test' "$e7_script" 2>/dev/null; then
      _red "session-resumer" "session-resumer.sh has no --self-test entrypoint"
    fi
    if command -v schtasks >/dev/null 2>&1; then
      if MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-session-resumer" >/dev/null 2>&1; then
        :
      else
        _warn "session-resumer" "scheduled task 'NL-session-resumer' not registered — documented (see session-resumer.sh header), not registered. Honest warn until specs-e §E.W.6 runs on this machine."
      fi
    fi
  fi

  # --- E.8: nl-issue.sh (predicate 1: exists+executable; predicate 2:
  # digest wiring grep, absence-tolerant on the digest hook itself). ---
  local e8_script="${live_home}/scripts/nl-issue.sh"
  if [[ ! -f "$e8_script" ]]; then
    _warn "wave-e-e8-nl-issue" "nl-issue.sh missing from live mirror at ${e8_script} — E.8 not yet installed on this machine"
  elif [[ ! -x "$e8_script" ]]; then
    _red "wave-e-e8-nl-issue" "nl-issue.sh exists but is not executable at ${e8_script}"
  fi
  if [[ -f "$e1_hook" ]]; then
    if ! grep -q "nl-issue.sh" "$e1_hook" 2>/dev/null; then
      _red "wave-e-e8-nl-issue" "session-start-digest.sh exists but does not wire nl-issue.sh (silent no-op digest feed)"
    fi
  fi

  # --- E.9: context-watermark.sh + pre-compact-continuity.sh (hook
  # presence + PostToolUse/PreCompact template wiring + handoff dir
  # writable). Mirrors check_wave_e_e9_precompaction from the fragment. ---
  local e9_template=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/settings.json.template" ]] \
    && e9_template="${repo_root}/adapters/claude-code/settings.json.template"
  [[ -z "$e9_template" && -f "${live_home}/settings.json" ]] && e9_template="${live_home}/settings.json"

  # E.9 predicates are scoped to fire ONLY when the template actually wires
  # (or is expected to wire) these hooks — an unrelated settings.json
  # fixture (pre-Wave-E, or a doctor self-test fixture built for a
  # different check) that never mentions either hook name is simply
  # "E.9 not yet installed on this machine" (WARN, tolerate-absent — same
  # contract as the E.1/E.7/E.8 sub-checks above), NOT a RED. RED is
  # reserved for the case the fragment calls "the primary signal": the
  # template DOES reference one of the two hooks (so E.9 wiring was
  # attempted) but is missing the OTHER hook, missing a matcher, or the
  # hook file itself is absent from disk despite being wired.
  local e9_cw_wired=0 e9_pc_wired=0
  if [[ -n "$e9_template" ]]; then
    grep -q 'context-watermark\.sh' "$e9_template" 2>/dev/null && e9_cw_wired=1
    grep -q 'pre-compact-continuity\.sh' "$e9_template" 2>/dev/null && e9_pc_wired=1
  fi

  if [[ -z "$e9_template" ]]; then
    _warn "wave-e-e9-precompaction" "no settings template/live settings resolved — skipped"
  elif [[ "$e9_cw_wired" -eq 0 && "$e9_pc_wired" -eq 0 ]]; then
    _warn "wave-e-e9-precompaction" "neither context-watermark.sh nor pre-compact-continuity.sh referenced in ${e9_template} — E.9 not yet installed/wired on this machine"
  else
    local e9_hooks_dir="${repo_root}/adapters/claude-code/hooks"
    [[ -d "$e9_hooks_dir" ]] || e9_hooks_dir="${live_home}/hooks"
    if [[ ! -f "${e9_hooks_dir}/context-watermark.sh" ]]; then
      _red "wave-e-e9-precompaction" "context-watermark.sh missing from ${e9_hooks_dir} — run: bash install.sh (or restore from adapters/claude-code/hooks/)"
    fi
    if [[ ! -f "${e9_hooks_dir}/pre-compact-continuity.sh" ]]; then
      _red "wave-e-e9-precompaction" "pre-compact-continuity.sh missing from ${e9_hooks_dir} — run: bash install.sh (or restore from adapters/claude-code/hooks/)"
    fi

    if [[ "$e9_cw_wired" -eq 0 ]]; then
      _red "wave-e-e9-precompaction" "context-watermark.sh not wired into PostToolUse — add a PostToolUse entry (matcher covering all tools) invoking ~/.claude/hooks/context-watermark.sh"
    fi

    if [[ "$e9_pc_wired" -eq 0 ]]; then
      _red "wave-e-e9-precompaction" "pre-compact-continuity.sh not wired into PreCompact — add PreCompact entries for both auto and manual matchers invoking ~/.claude/hooks/pre-compact-continuity.sh"
    elif command -v node >/dev/null 2>&1; then
      local e9_matchers
      # NL-FINDING-033: feed the file via STDIN (fd 0), not as a path arg —
      # native Windows node cannot resolve MSYS paths ('/c/Users/...' becomes
      # 'C:\c\User...' → ENOENT → silent false-empty → false RED), whereas the
      # MSYS `cat` reads the path fine. Reading stdin sidesteps translation.
      e9_matchers="$(cat "$e9_template" 2>/dev/null | node -e "
        const fs=require('fs');
        let cfg;
        try { cfg = JSON.parse(fs.readFileSync(0,'utf8')); } catch(e) { process.exit(0); }
        const pc = (cfg.hooks && cfg.hooks.PreCompact) || [];
        console.log(pc.map(b => b.matcher).join(','));
      " 2>/dev/null)"
      if ! printf '%s' "$e9_matchers" | grep -q 'auto' || ! printf '%s' "$e9_matchers" | grep -q 'manual'; then
        _red "wave-e-e9-precompaction" "PreCompact chain missing one of the auto/manual matchers (found: '${e9_matchers}') — pre-compact-continuity.sh must be wired on BOTH"
      fi
    fi

    local e9_handoff_dir="${HOME:-}/.claude/state/session-handoff"
    if ! mkdir -p "$e9_handoff_dir" 2>/dev/null || ! touch "${e9_handoff_dir}/.doctor-write-probe" 2>/dev/null; then
      _red "wave-e-e9-precompaction" "session-handoff directory not writable: ${e9_handoff_dir} — check permissions"
    else
      rm -f "${e9_handoff_dir}/.doctor-write-probe" 2>/dev/null || true
    fi
  fi

  # E.6 (needs-you.sh) doctor predicate — implemented at §E.W integration
  # verbatim per adapters/claude-code/tests/fixtures/wave-e/E.6/doctor-predicate.md
  # (Predicate 1: script exists+executable+--self-test; Predicate 2: NEEDS-YOU.md
  # freshness ≤7d whenever an Awaiting-decision item is open — tolerate-absent when
  # the ledger has never been created). (E.5 harness-kpis predicate remains an
  # optional follow-up; E.5's Done-when was met without a doctor check.)
  #
  # NL-FINDING (F.1 fix, found running the doctor's own --self-test on
  # master before this wave's changes): predicate 1 used to RED
  # unconditionally when needs-you.sh was absent, instead of the
  # tolerate-absent WARN every sibling E.1/E.7/E.8/E.9 sub-check uses for
  # "not yet installed on THIS machine/fixture" — a bare mktemp -d fixture
  # (every self-test scenario in this file) naturally lacks
  # scripts/needs-you.sh, so this made check_wave_e_surfaces RED on every
  # single self-test scenario regardless of what that scenario was
  # actually testing, masking real self-test signal entirely. Also fixed:
  # ny_state read from literal "${HOME}" instead of the passed-in
  # live_home, so a self-test run (which sandboxes via
  # HARNESS_DOCTOR_HOME, not HOME) leaked the REAL machine's
  # needs-you ledger into every fixture's verdict (the same class of bug
  # as NL-FINDING-025/028 — self-test state must never escape to the real
  # machine's paths).
  local ny_script="${repo_root}/adapters/claude-code/scripts/needs-you.sh"
  if [[ ! -f "$ny_script" ]]; then
    _warn "wave-e-e6-needs-you" "needs-you.sh missing at ${ny_script} — E.6 not yet installed on this machine"
  elif [[ ! -x "$ny_script" ]]; then
    _red "wave-e-e6-needs-you" "needs-you.sh present but not executable — chmod +x ${ny_script}"
  elif ! grep -q -- '--self-test' "$ny_script"; then
    _red "wave-e-e6-needs-you" "needs-you.sh missing a --self-test entrypoint despite its manifest selftest claim"
  fi
  local ny_nlpaths="${repo_root}/adapters/claude-code/hooks/lib/nl-paths.sh"
  local ny_main_root=""
  [[ -f "$ny_nlpaths" ]] && ny_main_root=$(bash -c "source '$ny_nlpaths'; nl_main_checkout_root" 2>/dev/null)
  [[ -n "$ny_main_root" ]] || ny_main_root="$repo_root"
  local ny_md="${ny_main_root}/NEEDS-YOU.md"
  local ny_state="${live_home}/state/needs-you/ledger.json"
  if [[ -f "$ny_state" ]] && command -v jq >/dev/null 2>&1; then
    local ny_open
    ny_open=$(jq '[.items[] | select(.section == "decision" and .state == "open")] | length' "$ny_state" 2>/dev/null || echo 0)
    if [[ "${ny_open:-0}" -gt 0 ]]; then
      if [[ ! -f "$ny_md" ]]; then
        _red "wave-e-e6-needs-you" "NEEDS-YOU.md missing at main-checkout root (${ny_md}) despite ${ny_open} open decision item(s) — run: bash adapters/claude-code/scripts/needs-you.sh render"
      else
        local ny_now ny_mtime ny_age
        ny_now=$(date -u +%s)
        ny_mtime=$(stat -c %Y "$ny_md" 2>/dev/null || stat -f %m "$ny_md" 2>/dev/null || echo 0)
        ny_age=$(( ny_now - ny_mtime ))
        if [[ "$ny_age" -gt $((7 * 86400)) ]]; then
          _red "wave-e-e6-needs-you" "NEEDS-YOU.md is $((ny_age / 86400))d stale despite ${ny_open} open decision item(s) — run: bash adapters/claude-code/scripts/needs-you.sh render"
        fi
      fi
    fi
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: heartbeat-task (NL-FINDING-022, specs-e §E.10 item 6 — DECISION:
# WIRE). Verifies the `NL-workstreams-heartbeat` scheduled task exists.
# WARN (not RED) when schtasks is unavailable (non-Windows) or the task
# is not yet registered (honest-status territory pre-§E.W, mirrors the
# E.7 session-resumer predicate's own WARN rationale) — this doctor
# check's job is "did install.sh's registration code run/succeed", not
# "punish a machine that hasn't run install.sh since this task shipped".
# ------------------------------------------------------------
check_heartbeat_task() {
  local live_home="$1" repo_root="$2"
  if ! command -v schtasks >/dev/null 2>&1; then
    _warn "heartbeat-task" "schtasks not available on this platform — scheduled-task check skipped (non-Windows)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-workstreams-heartbeat" >/dev/null 2>&1; then
    :
  else
    _warn "heartbeat-task" "scheduled task 'NL-workstreams-heartbeat' not registered — run: bash adapters/claude-code/install.sh (registers workstreams-emit.sh --heartbeat every 5 min)"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: untracked-dirt-ignore-rule (NL-FINDING-026 class 2, specs-e
# §E.10 item 9). Verifies the ignore rule work-integrity-gate's check (c)
# now hard-codes (grep -v .claude/state) is ALSO backed by this repo's own
# .gitignore, so a governed repo relying on .gitignore (rather than the
# gate's built-in exclusion alone) stays honest. WARN (not RED) when the
# repo is unresolved — this is a hygiene check on the governed repo the
# doctor is running against, not a hard gate on every possible caller.
# ------------------------------------------------------------
check_untracked_dirt_ignore_rule() {
  local repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "untracked-dirt-ignore-rule" "repo root unresolved — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  local gi="${repo_root}/.gitignore"
  if [[ ! -f "$gi" ]]; then
    _warn "untracked-dirt-ignore-rule" "no .gitignore found at ${gi} — cannot verify .claude/state/ ignore rule (work-integrity-gate's check-c exclusion still applies unconditionally as a code-level fallback)"
  elif ! grep -qE '(^|[^#])\.claude/state/?[[:space:]]*$' "$gi" 2>/dev/null; then
    _warn "untracked-dirt-ignore-rule" ".gitignore at ${gi} does not appear to ignore .claude/state/ — work-integrity-gate's check-c grep -v exclusion covers this in code, but the repo's own .gitignore should too (NL-FINDING-026 class 2)"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: pin-f-waiver-purpose-clauses (ADR 058 D5 pin f, specs-e §E.10
# item 2). Every waiver-accepting hook must validate the two named
# clauses ("this gate exists to prevent X" / "that does not apply here
# because Y") via the shared _wig_check_waiver-style helper (or an
# equivalent per-hook implementation). This doctor check is a GREP
# assertion, not a runtime probe: it verifies each hook enumerated by
# `rg -l "waiver" hooks/*.sh` actually references a purpose-clause
# validation routine, so a future waiver-accepting hook added WITHOUT
# purpose-clause validation is caught structurally.
# ------------------------------------------------------------
check_pin_f_waiver_purpose_clauses() {
  local repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "pin-f-waiver-purpose-clauses" "repo root unresolved — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  local hooks_dir="${repo_root}/adapters/claude-code/hooks"
  [[ -d "$hooks_dir" ]] || { _warn "pin-f-waiver-purpose-clauses" "no repo hooks/ directory at ${hooks_dir} — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local f
  for f in "$hooks_dir"/*.sh; do
    [[ -f "$f" ]] || continue
    # Narrow signal (not a bare "waiver" mention — that false-positives on
    # comments about REMOVED waiver paths, self-tests asserting a waiver
    # string is ABSENT, and unrelated "waiver-density" telemetry, none of
    # which are waiver-reading hooks): a hook that actually READS a waiver
    # file as an escape hatch names a `*-waiver-*`/`*-attested-*`/
    # `*-approved-*` filename pattern somewhere (a `find -name` probe, a
    # `WAIVER_GLOB=` variable, a `compgen -G` check, or a native bash glob
    # loop `for f in dir/prefix-*.txt`) — the union of shapes every real
    # waiver reader in this repo uses (work-integrity-gate.sh,
    # workstreams-state-gate.sh, workstreams-stop-gate.sh,
    # teammate-spawn-validator.sh, workstreams-task-binding.sh,
    # bug-persistence-gate.sh).
    grep -qE '(waiver-|attested-|approved-)[A-Za-z0-9._$*{}-]*\.txt' "$f" 2>/dev/null || continue
    # A file that reads a waiver family purely as a downstream SIGNAL (not
    # as its own escape hatch — the family is validated where it is
    # written/honored by a DIFFERENT gate) can declare that explicitly with
    # a `pin-f-doctor-exempt:` marker comment naming why, rather than
    # re-implementing/re-referencing a validator it doesn't own.
    grep -qE 'pin-f-doctor-exempt' "$f" 2>/dev/null && continue
    # Every waiver-reading hook must reference the shared purpose-clause
    # validator (_wig_check_waiver, waiver_has_purpose_clauses per pin-f)
    # OR its own inline purpose-clause validation marker.
    if ! grep -qE '_wig_check_waiver|waiver_has_purpose_clauses|_check_waiver_purpose_clauses|purpose[-_ ]clause' "$f" 2>/dev/null; then
      _warn "pin-f-waiver-purpose-clauses" "$(basename "$f") reads a waiver-family file but does not reference a purpose-clause validator (_wig_check_waiver / waiver_has_purpose_clauses / a 'purpose-clause' marker / a 'pin-f-doctor-exempt' comment) — pin (f) requires validating 'this gate exists to prevent X' + 'that does not apply here because Y'"
    fi
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-chains (Wave F, task F.1, specs-f §F.1 item 1)
# Stop <= 6, SessionStart <= 8 chain entries, checked against BOTH the
# committed template and the live settings.json. A single check id
# ("budget-chains") consolidates what earlier waves only discussed in
# comments (session-start-surfacer-pack.sh's header note) — there was no
# prior mechanical enforcement to "consolidate" other than that comment,
# so this is the first real implementation under the budget-chains id.
# Counts TOTAL hook entries across every matcher block for the event
# (not matcher-block count), matching how Claude Code actually executes
# the chain (every hooks[] entry in every matching block runs).
# ------------------------------------------------------------
_count_chain_entries() {
  # $1 = settings.json path, $2 = event name (Stop|SessionStart) -> prints total hook count (or empty on parse failure)
  local settings="$1" event="$2"
  [[ -f "$settings" ]] || { printf ''; return 0; }
  if command -v node >/dev/null 2>&1; then
    cat "$settings" 2>/dev/null | node -e "
      const fs = require('fs');
      let cfg;
      try { cfg = JSON.parse(fs.readFileSync(0, 'utf8')); } catch (e) { process.exit(0); }
      const arr = (cfg.hooks && cfg.hooks['$event']) || [];
      let total = 0;
      for (const block of arr) total += (block.hooks || []).length;
      console.log(total);
    " 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then
    jq -r --arg ev "$event" '[(.hooks[$ev] // [])[] | (.hooks // []) | length] | add // 0' "$settings" 2>/dev/null
  else
    printf ''
  fi
}

check_budget_chains() {
  local live_home="$1" repo_root="$2"
  local live_settings="${live_home}/settings.json"
  local template_settings="${repo_root}/adapters/claude-code/settings.json.template"

  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "budget-chains" "neither node nor jq available — chain-length budgets skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local src path event count max
  for src in live template; do
    if [[ "$src" == "live" ]]; then path="$live_settings"; else path="$template_settings"; fi
    if [[ ! -f "$path" ]]; then
      _warn "budget-chains" "${src} settings.json not found at ${path} — skipped for ${src}"
      continue
    fi
    for event in Stop SessionStart; do
      if [[ "$event" == "Stop" ]]; then max=6; else max=8; fi
      count="$(_count_chain_entries "$path" "$event")"
      if [[ -z "$count" ]]; then
        _warn "budget-chains" "could not parse ${event} chain length from ${src} settings (${path})"
        continue
      fi
      if [[ "$count" -gt "$max" ]]; then
        _red "budget-chains" "${event} chain has ${count} hook entries in ${src} settings (budget <= ${max}) — ${path}"
      fi
    done
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-blocking-gates (Wave F, task F.1, specs-f §F.1 item 2)
# Blocking gates <= 12: count manifest entries with blocking:true.
# ------------------------------------------------------------
check_budget_blocking_gates() {
  local live_home="$1" repo_root="$2"
  local manifest
  if ! manifest="$(resolve_manifest "$live_home" "$repo_root")"; then
    _warn "budget-blocking-gates" "no manifest.json found (live mirror or repo) — skipped (pre-C.1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "budget-blocking-gates" "neither node nor jq available — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local count max=12
  if command -v node >/dev/null 2>&1; then
    count="$(node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
console.log((m.entries || []).filter(e => e.blocking === true).length);
' "$manifest" 2>/dev/null)"
  else
    count="$(jq '[.entries[] | select(.blocking == true)] | length' "$manifest" 2>/dev/null)"
  fi
  [[ -z "$count" ]] && { _warn "budget-blocking-gates" "could not count blocking entries in ${manifest}"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  if [[ "$count" -gt "$max" ]]; then
    _red "budget-blocking-gates" "${count} manifest entries have blocking:true (budget <= ${max}) — ${manifest}; remediation: demote via scripts/gate-demotion.sh (F.5) or consolidate per ADR 059 D7"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-always-loaded (Wave F, task F.1, specs-f §F.1 item 3)
# Always-loaded <= 30KB: byte-sum of ~/.claude/rules/*.md + CLAUDE.md.
# This is a DEDICATED, always-strict 30KB rule (independent of the
# existing configurable check_byte_budget/~/.claude/local/doctor-budget
# mechanism, which stays as the machine-tunable soft-by-default check) —
# specs-f §F.1 item 3 names an exact, non-configurable threshold.
# ------------------------------------------------------------
check_budget_always_loaded() {
  local live_home="$1"
  local rules_dir="${live_home}/rules"
  local claude_md="${live_home}/CLAUDE.md"
  local max=30000

  if [[ ! -d "$rules_dir" && ! -f "$claude_md" ]]; then
    _warn "budget-always-loaded" "neither ${rules_dir} nor ${claude_md} exist — nothing to check"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local total
  total="$( { cat "$rules_dir"/*.md 2>/dev/null; cat "$claude_md" 2>/dev/null; } | wc -c | tr -d '[:space:]')"
  total="${total:-0}"

  if [[ "$total" -gt "$max" ]]; then
    _red "budget-always-loaded" "${total} bytes across ~/.claude/rules/*.md + CLAUDE.md exceeds the always-loaded budget of ${max} bytes — move content to doctrine/ (JIT-delivered) per constitution §10"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-active-plans (Wave F, task F.1, specs-f §F.1 item 4)
# ACTIVE plans <= 3 machine-wide: `grep -l "^Status: ACTIVE" docs/plans/*.md
# | wc -l` across every repo listed in ~/.claude/local/nl-repo-path +
# registered project roots.
#
# EXACT ROOT LIST THIS CHECK WALKS (documented per spec's explicit
# requirement):
#   1. The repo_root passed in (this invocation's own resolved repo).
#   2. The single line in <live_home>/local/nl-repo-path, if that file
#      exists and names a readable directory (this machine's canonical
#      NL checkout — see hooks/lib/nl-paths.sh's identical resolution;
#      live_home is $HOME/.claude, overridable to a sandbox root via
#      HARNESS_DOCTOR_HOME exactly like every other live-mirror read in
#      this file — self-test fixtures must never leak the REAL machine's
#      nl-repo-path into a fixture's verdict).
#   3. Every line in <live_home>/local/nl-project-roots (one absolute path
#      per line, '#'-comments and blanks skipped) IF that file exists —
#      this is the "registered project roots" extension point named by
#      the spec; no such file exists on this machine today (single-repo
#      machine), so this tier is a no-op here but is honestly documented
#      and wired for a future multi-repo machine.
# Duplicate roots (e.g. repo_root == nl-repo-path on a single-repo
# machine) are counted once. Fail-open per spec: an unreadable/missing
# root contributes 0 to the count (WARN, not RED) rather than aborting
# the whole check.
# ------------------------------------------------------------
_budget_active_plans_roots() {
  # Emits the de-duplicated list of candidate roots, one per line.
  local repo_root="$1" live_home="$2"
  local -a roots=()
  [[ -n "$repo_root" ]] && roots+=("$repo_root")

  local cfg="${live_home}/local/nl-repo-path"
  if [[ -f "$cfg" ]]; then
    local line
    line="$(head -1 "$cfg" 2>/dev/null | tr -d '\r')"
    [[ -n "$line" ]] && roots+=("$line")
  fi

  local extra="${live_home}/local/nl-project-roots"
  if [[ -f "$extra" ]]; then
    local rline
    while IFS= read -r rline; do
      rline="${rline%$'\r'}"
      [[ -z "$rline" ]] && continue
      [[ "$rline" == \#* ]] && continue
      roots+=("$rline")
    done < "$extra"
  fi

  printf '%s\n' "${roots[@]}" | sort -u | grep -v '^$'
}

check_budget_active_plans() {
  local live_home="$1" repo_root="$2"
  local max=3
  local roots
  roots="$(_budget_active_plans_roots "$repo_root" "$live_home")"
  if [[ -z "$roots" ]]; then
    _warn "budget-active-plans" "no roots resolved (repo_root unset, no <live_home>/local/nl-repo-path) — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local total=0 root plans_dir n unreadable=()
  while IFS= read -r root; do
    [[ -z "$root" ]] && continue
    plans_dir="${root}/docs/plans"
    if [[ ! -d "$plans_dir" || ! -r "$plans_dir" ]]; then
      unreadable+=("$root")
      continue
    fi
    n=0
    local f
    for f in "$plans_dir"/*.md; do
      [[ -f "$f" ]] || continue
      head -n 30 "$f" 2>/dev/null | grep -qE '^Status:[[:space:]]*ACTIVE' && n=$((n + 1))
    done
    total=$((total + n))
  done <<< "$roots"

  if [[ "${#unreadable[@]}" -gt 0 ]]; then
    _warn "budget-active-plans" "$(IFS=,; echo "${unreadable[*]}") had no readable docs/plans/ — counted as 0 (fail-open)"
  fi

  if [[ "$total" -gt "$max" ]]; then
    _red "budget-active-plans" "${total} plans with Status: ACTIVE across $(printf '%s' "$roots" | grep -c .) root(s) (budget <= ${max}) — defer/complete/abandon via the F.3-style disposition process"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-worktrees-branches (Wave F, task F.1, specs-f §F.1 item 5)
# Worktree count <= 6 and none older than 7 days without a commit; local
# branches with no upstream and no commit in 7 days flagged.
# ------------------------------------------------------------
check_budget_worktrees_branches() {
  local repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "budget-worktrees-branches" "repo root unresolved — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  command -v git >/dev/null 2>&1 || { _warn "budget-worktrees-branches" "git not available — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local max_worktrees=6
  local stale_secs=$((7 * 86400))
  local now; now=$(date +%s)

  # --- worktree count + age ---
  local wt_list
  wt_list="$(git -C "$repo_root" worktree list --porcelain 2>/dev/null)"
  if [[ -z "$wt_list" ]]; then
    _warn "budget-worktrees-branches" "git worktree list produced no output — skipped worktree sub-check"
  else
    local wt_count
    wt_count="$(printf '%s\n' "$wt_list" | grep -c '^worktree ')"
    if [[ "$wt_count" -gt "$max_worktrees" ]]; then
      _red "budget-worktrees-branches" "${wt_count} git worktrees registered (budget <= ${max_worktrees}) — prune with: git worktree prune; git worktree remove <stale-path>"
    fi

    # Per-worktree staleness: no commit in 7 days on that worktree's HEAD.
    local wt_path=""
    while IFS= read -r line; do
      case "$line" in
        "worktree "*) wt_path="${line#worktree }" ;;
        "HEAD "*)
          local sha ts age
          sha="${line#HEAD }"
          [[ -z "$wt_path" ]] && continue
          [[ "$wt_path" == "$repo_root" ]] && continue  # main checkout is not a "worktree" for this budget
          ts="$(git -C "$repo_root" log -1 --format=%ct "$sha" 2>/dev/null)"
          [[ -z "$ts" ]] && continue
          age=$((now - ts))
          if [[ "$age" -ge "$stale_secs" ]]; then
            _red "budget-worktrees-branches" "worktree ${wt_path} has no commit in $((age / 86400))d (budget: 7d) — remove with: git worktree remove '${wt_path}'"
          fi
          ;;
      esac
    done <<< "$wt_list"
  fi

  # --- local branch staleness: no upstream + no commit in 7 days ---
  local br_list
  br_list="$(git -C "$repo_root" for-each-ref --format='%(refname:short)|%(upstream:short)|%(committerdate:unix)' refs/heads/ 2>/dev/null)"
  if [[ -n "$br_list" ]]; then
    local name upstream ts age
    while IFS='|' read -r name upstream ts; do
      [[ -z "$name" ]] && continue
      [[ -n "$upstream" ]] && continue
      [[ -z "$ts" ]] && continue
      age=$((now - ts))
      if [[ "$age" -ge "$stale_secs" ]]; then
        _red "budget-worktrees-branches" "branch '${name}' has no upstream and no commit in $((age / 86400))d (budget: 7d) — push it (git push -u origin ${name}) or delete it (git branch -D ${name})"
      fi
    done <<< "$br_list"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: new-gate-evidence-bar (Wave F, task F.1, specs-f §F.1 item 3 /
# ADR 059 D4 — the DOCTOR side; constitution §10's prose side is
# ORCHESTRATOR-ONLY and shipped separately). Any manifest entry with
# `added_after: 2026-07` (or any value >= "2026-07" lexicographically —
# the field is a YYYY-MM string) must carry golden_scenario,
# fp_expectation, retirement_condition, and (waiver_path OR
# honesty_rationale). RED otherwise. Graceful WARN when no manifest, no
# parser, or the manifest schema does not yet declare these fields (this
# doctor check does not itself require the schema/manifest to carry the
# fields — it degrades to "no added_after entries found" silently, since
# a manifest with zero added_after entries has nothing to validate).
# ------------------------------------------------------------
check_new_gate_evidence_bar() {
  local live_home="$1" repo_root="$2"
  local manifest
  if ! manifest="$(resolve_manifest "$live_home" "$repo_root")"; then
    _warn "new-gate-evidence-bar" "no manifest.json found — skipped (pre-C.1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "new-gate-evidence-bar" "neither node nor jq available — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out
  if command -v node >/dev/null 2>&1; then
    out="$(node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const problems = [];
for (const e of m.entries || []) {
  const addedAfter = e.added_after;
  if (typeof addedAfter !== "string" || addedAfter.trim().length === 0) continue;
  if (addedAfter < "2026-07") continue;
  const missing = [];
  if (typeof e.golden_scenario !== "string" || e.golden_scenario.trim().length === 0) missing.push("golden_scenario");
  if (typeof e.fp_expectation !== "string" || e.fp_expectation.trim().length === 0) missing.push("fp_expectation");
  if (typeof e.retirement_condition !== "string" || e.retirement_condition.trim().length === 0) missing.push("retirement_condition");
  const hasWaiverPath = typeof e.waiver_path === "string" && e.waiver_path.trim().length > 0;
  const hasHonestyRationale = typeof e.honesty_rationale === "string" && e.honesty_rationale.trim().length > 0;
  if (!hasWaiverPath && !hasHonestyRationale) missing.push("waiver_path-or-honesty_rationale");
  if (missing.length) problems.push(e.id + ": missing " + missing.join(", "));
}
for (const p of problems) console.log(p);
' "$manifest" 2>/dev/null)"
  else
    out="$(jq -r '
.entries[] | select((.added_after // "") >= "2026-07") as $e |
(
  [ (if (($e.golden_scenario // "") | length) > 0 then empty else "golden_scenario" end),
    (if (($e.fp_expectation // "") | length) > 0 then empty else "fp_expectation" end),
    (if (($e.retirement_condition // "") | length) > 0 then empty else "retirement_condition" end),
    (if ((($e.waiver_path // "") | length) > 0) or ((($e.honesty_rationale // "") | length) > 0) then empty else "waiver_path-or-honesty_rationale" end)
  ] | select(length > 0)
) as $missing | select(($missing | length) > 0) | "\($e.id): missing \($missing | join(\", \"))"
' "$manifest" 2>/dev/null)"
  fi

  if [[ -n "$out" ]]; then
    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      _red "new-gate-evidence-bar" "${line} (added_after >= 2026-07 requires the full evidence bar per ADR 059 D4)"
    done <<< "$out"
  fi
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
# Check 8: selftest-sweep (--full only)
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
    # 120s killed passing-but-slow suites on Windows (git-heavy scenarios measured
    # 4-8 min; NL-FINDING-018-era doctor --full run), and 600s killed plan-reviewer
    # (green standalone at 987s, measured 2026-07-03). Default 1500 (~1.5x slowest
    # measured suite), env-overridable; per-hook budgets via manifest = E-wave.
    out="$(HARNESS_SELFTEST=1 timeout "${DOCTOR_SELFTEST_TIMEOUT:-1500}" bash "$hook" --self-test </dev/null 2>&1)"
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
# run_quick_checks — checks 1-7 against the given live_home/repo_root
# ------------------------------------------------------------
run_quick_checks() {
  local live_home="$1" repo_root="$2"
  check_wiring_resolves "$live_home" "$repo_root"
  check_lib_deps "$live_home"
  check_legacy_paths "$live_home"
  check_template_live_drift "$live_home" "$repo_root"
  check_claim_honesty "$live_home" "$repo_root"
  check_byte_budget "$live_home"
  check_manifest "$live_home" "$repo_root"
  check_manifest_freshness "$live_home" "$repo_root"
  check_wave_e_surfaces "$live_home" "$repo_root"
  check_heartbeat_task "$live_home" "$repo_root"
  check_untracked_dirt_ignore_rule "$live_home" "$repo_root"
  check_pin_f_waiver_purpose_clauses "$live_home" "$repo_root"
  check_budget_chains "$live_home" "$repo_root"
  check_budget_blocking_gates "$live_home" "$repo_root"
  check_budget_always_loaded "$live_home" "$repo_root"
  check_budget_active_plans "$live_home" "$repo_root"
  check_budget_worktrees_branches "$live_home" "$repo_root"
  check_new_gate_evidence_bar "$live_home" "$repo_root"
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
    mkdir -p "$dir/repo/adapters/claude-code/hooks" "$dir/repo/adapters/claude-code/scripts" \
             "$dir/repo/adapters/claude-code/rules" "$dir/repo/adapters/claude-code/schemas"
    printf '%s\n' "$dir"
  }

  # Copies the real manifest-check.sh + manifest schema into a fixture repo
  # so the doctor's check 7 (manifest-check invocation) can run there.
  # Returns 1 (caller should SKIP manifest scenarios) when the real tooling
  # is not present next to this doctor (e.g. a partial install).
  _copy_manifest_tooling() {
    local dir="$1"
    local checker_src="$SCRIPT_DIR/../scripts/manifest-check.sh"
    local schema_src="$SCRIPT_DIR/../schemas/manifest.schema.json"
    [[ -f "$checker_src" && -f "$schema_src" ]] || return 1
    cp "$checker_src" "$dir/repo/adapters/claude-code/scripts/manifest-check.sh"
    cp "$schema_src" "$dir/repo/adapters/claude-code/schemas/manifest.schema.json"
    return 0
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

  # Historical helper (pre-C.1 the claim-honesty check used an embedded
  # checklist that fixtures had to satisfy). Check 5 is manifest-driven now:
  # fixtures WITHOUT a manifest.json take the graceful-WARN path on both
  # check 5 and check 7, so unrelated scenarios need no stamping. Kept as a
  # no-op to keep the scenario bodies' shape stable.
  _stamp_claim_honesty_green() {
    :
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

  # Manifest fixture writer for the check-5/check-7 scenarios.
  #   $1 = fixture dir, $2 = variant: "green" | "no-honest" | "ghost-hook"
  # green      : wired gate (hook on disk+template+live) + pending gate with
  #              honest_status — passes both claim-honesty and manifest-check.
  # no-honest  : the pending gate LACKS honest_status -> claim-honesty RED.
  # ghost-hook : manifest references a hook absent from disk (honest_status
  #              present, so claim-honesty passes) -> manifest-check RED.
  _write_manifest_fixture() {
    local dir="$1" variant="$2"
    local pending_hook="pending-gate.sh" honest_line
    printf '#!/bin/bash\nexit 0\n' > "$dir/repo/adapters/claude-code/hooks/wired-gate.sh"
    printf '#!/bin/bash\nexit 0\n' > "$dir/live/hooks/wired-gate.sh"
    if [[ "$variant" == "ghost-hook" ]]; then
      pending_hook="ghost.sh"   # deliberately NOT created on disk
    else
      printf '#!/bin/bash\nexit 0\n' > "$dir/repo/adapters/claude-code/hooks/pending-gate.sh"
    fi
    if [[ "$variant" == "no-honest" ]]; then
      honest_line=""
    else
      honest_line='      "honest_status": "invoked via a chain script; not directly wired",'
    fi
    cat > "$dir/repo/adapters/claude-code/manifest.json" <<MANIFEST_EOF
{
  "schema_version": 1,
  "entries": [
    {
      "id": "wired-gate",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["wired-gate.sh"],
      "events": ["Stop"],
      "wired_template": true,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "budget_class": "stop"
    },
    {
      "id": "pending-gate",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["${pending_hook}"],
      "events": ["precommit"],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
${honest_line}
      "budget_class": "none"
    }
  ]
}
MANIFEST_EOF
    # no-honest variant leaves an empty line where honest_status was — strip
    # it so the JSON stays parseable.
    if [[ "$variant" == "no-honest" ]]; then
      grep -v '^$' "$dir/repo/adapters/claude-code/manifest.json" > "$dir/repo/adapters/claude-code/manifest.json.tmp" \
        && mv "$dir/repo/adapters/claude-code/manifest.json.tmp" "$dir/repo/adapters/claude-code/manifest.json"
    fi
    _write_settings "$dir/live/settings.json" "wired-gate.sh"
    cp "$dir/live/settings.json" "$dir/repo/adapters/claude-code/settings.json.template"
  }

  # ---- Check 5 (claim-honesty, manifest-driven): RED fixture — a manifest
  # gate has wired_template false and no honest_status ----
  D=$(_scenario_dir c5-red)
  if _copy_manifest_tooling "$D"; then :; fi
  _write_manifest_fixture "$D" no-honest
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "5-claim-honesty-red" 1 "$RC" "RED claim-honesty" "$OUT"

  # ---- Check 5: GREEN fixture — every manifest gate is either live-wired
  # or carries an honest_status ----
  D=$(_scenario_dir c5-green)
  if _copy_manifest_tooling "$D"; then :; fi
  _write_manifest_fixture "$D" green
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "5-claim-honesty-green" 0 "$RC" "" "$OUT"

  # ---- Check 7 (manifest-check invocation): RED fixture — the manifest
  # references a hook that does not exist on disk (claim-honesty itself is
  # satisfied via honest_status, so the RED must come from manifest-check) ----
  D=$(_scenario_dir c7m-red)
  if _copy_manifest_tooling "$D"; then
    _write_manifest_fixture "$D" ghost-hook
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "7-manifest-check-red" 1 "$RC" "RED manifest-check" "$OUT"
  else
    echo "self-test (7-manifest-check-red): SKIP — manifest-check.sh not present next to this doctor" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Check 7: GREEN fixture — a fully consistent manifest passes the
  # manifest-check invocation ----
  D=$(_scenario_dir c7m-green)
  if _copy_manifest_tooling "$D"; then
    _write_manifest_fixture "$D" green
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "7-manifest-check-green" 0 "$RC" "" "$OUT"
  else
    echo "self-test (7-manifest-check-green): SKIP — manifest-check.sh not present next to this doctor" >&2
    PASSED=$((PASSED + 1))
  fi

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

  # ---- Check: manifest-freshness (NL-FINDING-017, item 4). RED fixture —
  # live and repo manifest.json hash mismatch ----
  D=$(_scenario_dir mf-red)
  _stamp_claim_honesty_green "$D"
  echo '{"schema_version":1,"entries":[]}' > "$D/live/manifest.json"
  echo '{"schema_version":1,"entries":[],"drift":"repo-changed"}' > "$D/repo/adapters/claude-code/manifest.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "manifest-freshness-red" 1 "$RC" "RED manifest-freshness" "$OUT"

  # ---- Check: manifest-freshness GREEN fixture — identical hashes ----
  D=$(_scenario_dir mf-green)
  _stamp_claim_honesty_green "$D"
  echo '{"schema_version":1,"entries":[]}' > "$D/live/manifest.json"
  cp "$D/live/manifest.json" "$D/repo/adapters/claude-code/manifest.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "manifest-freshness-green" 0 "$RC" "" "$OUT"

  # ---- Check: heartbeat-task (NL-FINDING-022, item 6). Only meaningfully
  # exercisable on a machine with schtasks (Windows); elsewhere it WARNs
  # (skip) and this scenario is a no-op pass either way — a machine with
  # NO 'NL-workstreams-heartbeat' task registered must not RED (WARN only). ----
  D=$(_scenario_dir hb-warn)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "heartbeat-task-unregistered-warns-not-red" 0 "$RC" "" "$OUT"

  # ---- Check: untracked-dirt-ignore-rule (NL-FINDING-026 class 2, item 9).
  # RED-equivalent (WARN) fixture — repo .gitignore does NOT ignore
  # .claude/state/ ----
  D=$(_scenario_dir udi-warn)
  _stamp_claim_honesty_green "$D"
  echo "node_modules/" > "$D/repo/.gitignore"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "untracked-dirt-ignore-rule-missing-warns" 0 "$RC" "WARN untracked-dirt-ignore-rule" "$OUT"

  # ---- Check: untracked-dirt-ignore-rule GREEN fixture — .gitignore DOES
  # cover .claude/state/ ----
  D=$(_scenario_dir udi-green)
  _stamp_claim_honesty_green "$D"
  printf 'node_modules/\n.claude/state/\n' > "$D/repo/.gitignore"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "untracked-dirt-ignore-rule-present-green" 0 "$RC" "" "$OUT"

  # ---- Check: pin-f-waiver-purpose-clauses (ADR 058 D5 pin f, item 2).
  # RED-equivalent (WARN) fixture — a repo hook reads a waiver with no
  # purpose-clause validator referenced ----
  D=$(_scenario_dir pf-warn)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/hooks/legacy-waiver-reader.sh" <<'EOF'
#!/bin/bash
# reads a waiver file with only an existence+freshness check
if find .claude/state -name 'foo-waiver-*.txt' -newermt '1 hour ago' | grep -q .; then
  exit 0
fi
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "pin-f-waiver-purpose-clauses-missing-warns" 0 "$RC" "WARN pin-f-waiver-purpose-clauses" "$OUT"

  # ---- Check: pin-f-waiver-purpose-clauses GREEN fixture — the hook
  # references the shared purpose-clause validator ----
  D=$(_scenario_dir pf-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/hooks/modern-waiver-reader.sh" <<'EOF'
#!/bin/bash
# reads a waiver file, routed through waiver_has_purpose_clauses
if waiver_has_purpose_clauses ".claude/state/foo-waiver-x.txt"; then
  exit 0
fi
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "pin-f-waiver-purpose-clauses-present-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-chains (Wave F, F.1). RED fixture — Stop chain has
  # 7 entries (budget <= 6) in BOTH live and template. Dummy hook FILES are
  # created on both the live and repo sides so the unrelated wiring-resolves
  # check (which RED-fires on any referenced-but-missing hook) stays quiet —
  # this fixture is scoped to budget-chains only. ----
  _write_chain_settings() {
    # $1 = D (scenario dir), $2 = event (Stop|SessionStart), $3 = count, $4 = name prefix
    local d="$1" event="$2" n="$3" prefix="$4"
    local body="{\"hooks\":{\"${event}\":[{\"matcher\":\"*\",\"hooks\":["
    local i first=1
    for ((i = 0; i < n; i++)); do
      if [[ "$first" -eq 0 ]]; then body="${body},"; fi
      first=0
      body="${body}{\"type\":\"command\",\"command\":\"bash ~/.claude/hooks/${prefix}-${i}.sh\"}"
      echo '#!/bin/bash' > "$d/live/hooks/${prefix}-${i}.sh"
      echo '#!/bin/bash' > "$d/repo/adapters/claude-code/hooks/${prefix}-${i}.sh"
    done
    body="${body}]}]}}"
    printf '%s' "$body" > "$d/live/settings.json"
    cp "$d/live/settings.json" "$d/repo/adapters/claude-code/settings.json.template"
  }
  D=$(_scenario_dir bc-stop-red)
  _stamp_claim_honesty_green "$D"
  _write_chain_settings "$D" "Stop" 7 "stop-dummy"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-chains-stop-red" 1 "$RC" "RED budget-chains.*Stop chain has 7" "$OUT"

  # ---- Check: budget-chains GREEN fixture — Stop chain at 4 (within budget) ----
  D=$(_scenario_dir bc-stop-green)
  _stamp_claim_honesty_green "$D"
  _write_chain_settings "$D" "Stop" 4 "stop-dummy"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-chains-stop-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-chains RED fixture — SessionStart chain has 9 entries
  # (budget <= 8) ----
  D=$(_scenario_dir bc-ss-red)
  _stamp_claim_honesty_green "$D"
  _write_chain_settings "$D" "SessionStart" 9 "ss-dummy"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-chains-sessionstart-red" 1 "$RC" "RED budget-chains.*SessionStart chain has 9" "$OUT"

  # ---- Check: budget-blocking-gates. RED fixture — 13 manifest entries
  # with blocking:true (budget <= 12) ----
  _write_blocking_manifest_fixture() {
    local dir="$1" count="$2"
    local entries="" i
    for ((i = 0; i < count; i++)); do
      [[ -n "$entries" ]] && entries="${entries},"
      entries="${entries}{\"id\":\"gate-${i}\",\"kind\":\"gate\",\"doctrine_file\":null,\"hooks\":[],\"events\":[],\"wired_template\":false,\"selftest\":false,\"jit_triggers\":{\"paths\":[],\"keywords\":[]},\"blocking\":true,\"honest_status\":\"fixture stub\",\"budget_class\":\"none\"}"
    done
    printf '{"schema_version":1,"entries":[%s]}' "$entries" > "$dir/repo/adapters/claude-code/manifest.json"
  }
  D=$(_scenario_dir bbg-red)
  _stamp_claim_honesty_green "$D"
  _write_blocking_manifest_fixture "$D" 13
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-blocking-gates-red" 1 "$RC" "RED budget-blocking-gates.*13 manifest entries" "$OUT"

  # ---- Check: budget-blocking-gates GREEN fixture — 12 entries (at budget) ----
  D=$(_scenario_dir bbg-green)
  _stamp_claim_honesty_green "$D"
  _write_blocking_manifest_fixture "$D" 12
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-blocking-gates-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-always-loaded. RED fixture — rules + CLAUDE.md exceed
  # 30000 bytes ----
  D=$(_scenario_dir bal-red)
  _stamp_claim_honesty_green "$D"
  head -c 31000 /dev/zero | tr '\0' 'x' > "$D/live/rules/big.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-always-loaded-red" 1 "$RC" "RED budget-always-loaded" "$OUT"

  # ---- Check: budget-always-loaded GREEN fixture — well under 30000 bytes ----
  D=$(_scenario_dir bal-green)
  _stamp_claim_honesty_green "$D"
  echo "small" > "$D/live/rules/small.md"
  echo "small claude.md" > "$D/live/CLAUDE.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-always-loaded-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-active-plans. RED fixture — 4 ACTIVE plans in the
  # repo root's docs/plans/ (budget <= 3). The fixture's live/local/ has no
  # nl-repo-path file, so (post-fix) only repo_root itself is walked —
  # this is the isolation the live_home-scoping fix above guarantees. ----
  D=$(_scenario_dir bap-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/docs/plans"
  for i in 1 2 3 4; do
    printf '# Plan %d\nStatus: ACTIVE\n' "$i" > "$D/repo/docs/plans/p${i}.md"
  done
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-active-plans-red" 1 "$RC" "RED budget-active-plans.*4 plans" "$OUT"

  # ---- Check: budget-active-plans GREEN fixture — 3 ACTIVE plans (at budget) ----
  D=$(_scenario_dir bap-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/docs/plans"
  for i in 1 2 3; do
    printf '# Plan %d\nStatus: ACTIVE\n' "$i" > "$D/repo/docs/plans/p${i}.md"
  done
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-active-plans-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-worktrees-branches. RED fixture — a real throwaway
  # git repo with a stale (8-day-old, backdated commit) local branch with
  # no upstream. Worktree count/age sub-check needs `git worktree add`
  # which the doctor's own sandboxing doesn't otherwise exercise here, so
  # this fixture targets the branch-staleness half (worktree count <= 6 /
  # age is exercised implicitly — a single-worktree repo never trips it). ----
  D=$(_scenario_dir bwb-red)
  _stamp_claim_honesty_green "$D"
  # Epoch form ("@<unix-ts> +0000"), not "8 days ago" — GIT_AUTHOR_DATE/
  # GIT_COMMITTER_DATE do not accept git's free-form --date approxidate
  # syntax on every git build (confirmed non-parseable on this machine's
  # git 2.53; the epoch form is universally accepted).
  ( _bwb_stale_ts=$(( $(date -u +%s) - 8 * 86400 )) \
      && cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init \
      && git checkout --quiet -b stale-no-upstream-branch \
      && echo y > g && git add g \
      && GIT_AUTHOR_DATE="@${_bwb_stale_ts} +0000" GIT_COMMITTER_DATE="@${_bwb_stale_ts} +0000" git commit --quiet -m stale \
      && { git checkout --quiet master 2>/dev/null || git checkout --quiet main 2>/dev/null || true; }
  ) >/dev/null 2>&1
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-worktrees-branches-branch-red" 1 "$RC" "RED budget-worktrees-branches.*stale-no-upstream-branch" "$OUT"

  # ---- Check: budget-worktrees-branches GREEN fixture — a fresh branch
  # with a recent commit and no upstream (must NOT flag: <7d old) ----
  D=$(_scenario_dir bwb-green)
  _stamp_claim_honesty_green "$D"
  ( cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init \
      && git checkout --quiet -b fresh-no-upstream-branch \
      && echo y > g && git add g && git commit --quiet -m fresh \
      && git checkout --quiet master 2>/dev/null || git checkout --quiet main 2>/dev/null || true
  ) >/dev/null 2>&1
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-worktrees-branches-branch-green" 0 "$RC" "" "$OUT"

  # ---- Check: new-gate-evidence-bar. RED fixture — an added_after >=
  # 2026-07 entry missing the full evidence bar ----
  D=$(_scenario_dir nge-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "new-gate-incomplete",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": [],
      "events": [],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "honest_status": "fixture stub",
      "added_after": "2026-07",
      "budget_class": "none"
    }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "new-gate-evidence-bar-red" 1 "$RC" "RED new-gate-evidence-bar.*new-gate-incomplete" "$OUT"

  # ---- Check: new-gate-evidence-bar GREEN fixture — the full evidence bar
  # is present ----
  D=$(_scenario_dir nge-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "new-gate-complete",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": [],
      "events": [],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "honest_status": "fixture stub",
      "added_after": "2026-07",
      "golden_scenario": "Circuit incident 2026-07-03 cross-repo write",
      "fp_expectation": "legitimate cross-repo harness sessions must not warn",
      "retirement_condition": "zero fires for 30 days post-GA",
      "waiver_path": "fixture-waiver-*.txt",
      "budget_class": "none"
    }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "new-gate-evidence-bar-green" 0 "$RC" "" "$OUT"

  # ---- Check 8 (--full only): RED fixture — a stub hook's --self-test fails ----
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
  _assert "8-selftest-sweep-red" 1 "$RC" "RED selftest-sweep" "$OUT"

  # ---- Check 8: GREEN fixture — a stub hook's --self-test passes ----
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
  _assert "8-selftest-sweep-green" 0 "$RC" "" "$OUT"

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
