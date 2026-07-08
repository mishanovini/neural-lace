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
#   budget-blocking-gates   : <= 12 blocking session-event UNITS per the
#                             specs-d §D.0.4 frozen counting rule (wired_
#                             template:true + live-session event + same-
#                             class consolidation), via
#                             scripts/blocking-budget-check.js — NOT a bare
#                             count of blocking:true manifest entries (fixed
#                             during Wave-F integration; see the check's own
#                             header comment for the pre-fix defect).
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
# Check: wave-f-f2-docs (Wave F, task F.2) — doctor predicates from the F.2
# fragment, implemented VERBATIM per
# adapters/claude-code/tests/fixtures/wave-f/F.2/doctor-predicate.md.
#
# Predicate 1 — docs/harness-architecture.md byte-equals a fresh regen
# (gen-architecture-doc.sh --check). WARN (not RED) when the script itself
# is missing OR when it degrades gracefully (neither node nor jq present —
# same posture manifest-check.sh takes; distinguished from a real drift
# RED by grepping the script's own graceful-degradation WARN line so this
# check does not have to re-implement the node/jq probe).
#
# Predicate 2 — the five README surfaces named in the fragment each carry
# a `<!-- last-verified: YYYY-MM-DD (doctor-checked) -->` anchor no more
# than 90 days old. Implemented verbatim from the fragment's check command
# (same grep/date logic), inlined here rather than shelled out so it
# shares this file's _red/_warn accounting.
#
# Predicate 2b (doctrine/INDEX.md) and Predicate 3 (scripts/README.md
# carve-out) are handled by check_manifest / existing generator drift
# checks and documented-no-op respectively — the fragment itself notes
# both need no additional doctor code (see doctor-predicate.md).
# ------------------------------------------------------------
check_wave_f_f2_docs() {
  local live_home="$1" repo_root="$2"

  # --- Predicate 1: harness-architecture.md drift ---
  if [[ -z "$repo_root" ]]; then
    _warn "wave-f-f2-docs" "repo root unresolved — skipped harness-architecture.md drift check"
  else
    local gen_script="${repo_root}/adapters/claude-code/scripts/gen-architecture-doc.sh"
    if [[ ! -f "$gen_script" ]]; then
      _warn "wave-f-f2-docs" "gen-architecture-doc.sh missing from ${gen_script} — F.2 not yet installed on this machine"
    else
      local gen_out gen_rc
      gen_out="$(bash "$gen_script" --check 2>&1)"
      gen_rc=$?
      if printf '%s' "$gen_out" | grep -q 'WARN: needs node or jq'; then
        _warn "wave-f-f2-docs" "gen-architecture-doc.sh --check degraded (neither node nor jq available) — drift check skipped, same posture as manifest-check.sh"
      elif [[ "$gen_rc" -ne 0 ]]; then
        _red "wave-f-f2-docs" "docs/harness-architecture.md drift — gen-architecture-doc.sh --check exited ${gen_rc}: $(printf '%s' "$gen_out" | tail -n 1)"
      fi
    fi
  fi

  # --- Predicate 2: README freshness anchors, verbatim per the fragment ---
  # Absence-tolerant at the SURFACE level (same contract as the E.1/E.7/
  # E.8/E.9 wave-fragment sub-checks below): a fixture/machine where NONE
  # of the five README surfaces exist at all is "F.2 not yet installed
  # here" (WARN, not RED) — this is the shape every doctor self-test
  # fixture repo takes unless it explicitly opts into an F.2 scenario, and
  # a real repo pre-dating F.2 would otherwise RED on every one of the
  # five files for a doc-surface convention it never adopted. Once at
  # least one of the five exists, F.2 is "installed" on this
  # repo/fixture and every surface is held to the full predicate
  # (missing/no-anchor/stale all RED) — that is the partial-adoption case
  # the predicate exists to catch.
  if [[ -z "$repo_root" ]]; then
    _warn "wave-f-f2-docs" "repo root unresolved — skipped README freshness-anchor scan"
  else
    local -a f2_readmes=(
      "${repo_root}/README.md"
      "${repo_root}/adapters/claude-code/README.md"
      "${repo_root}/adapters/claude-code/attic/README.md"
      "${repo_root}/evals/README.md"
      "${repo_root}/neural-lace/workstreams-ui/README.md"
    )
    local f2_any_present=0
    for f in "${f2_readmes[@]}"; do
      [[ -f "$f" ]] && { f2_any_present=1; break; }
    done

    if [[ "$f2_any_present" -eq 0 ]]; then
      _warn "wave-f-f2-docs" "none of the five F.2 README surfaces present under ${repo_root} — F.2 not yet installed on this repo/fixture"
    else
      local today_epoch max_age_days=90
      today_epoch=$(date +%s)
      local f line date_str anchor_epoch age_days
      for f in "${f2_readmes[@]}"
      do
        if [[ ! -f "$f" ]]; then
          _red "wave-f-f2-docs" "MISSING README surface: ${f}"
          continue
        fi
        line="$(grep -m1 -E '<!-- last-verified: [0-9]{4}-[0-9]{2}-[0-9]{2} \(doctor-checked\) -->' "$f" 2>/dev/null)"
        if [[ -z "$line" ]]; then
          _red "wave-f-f2-docs" "NO-ANCHOR: ${f} missing '<!-- last-verified: YYYY-MM-DD (doctor-checked) -->'"
          continue
        fi
        date_str="$(printf '%s' "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
        anchor_epoch="$(date -d "$date_str" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null)"
        if [[ -z "$anchor_epoch" ]]; then
          _red "wave-f-f2-docs" "UNPARSEABLE-DATE: ${f} anchor date '${date_str}'"
          continue
        fi
        age_days=$(( (today_epoch - anchor_epoch) / 86400 ))
        if [[ "$age_days" -gt "$max_age_days" ]]; then
          _red "wave-f-f2-docs" "STALE (${age_days}d, budget <= ${max_age_days}d): ${f} — re-verify and bump the last-verified anchor"
        fi
      done
    fi
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

# ============================================================
# NL Observability Program Wave O, task O.6 (specs-o §O.6): six pipeline-
# health predicates. Spliced verbatim from
# tests/fixtures/wave-o/O.6/doctor-predicate.md (orchestrator integration,
# batch 2). Placement: immediately after check_untracked_dirt_ignore_rule,
# before check_pin_f_waiver_purpose_clauses, per the fragment's own
# suggested insertion point.
# ============================================================

# ------------------------------------------------------------
# Check: obs-writers-firing (specs-o §O.6 item 1). Ledger mtime <24h AND
# line-count grew since the doctor's own last-seen stamp
# (${live_home}/state/doctor-cache/obs-ledger-stamp.txt, self-updating).
# A ledger that exists but has gone stale/stopped-growing means every
# writer upstream silently died. First-ever run (stamp absent) always
# passes and just seeds the baseline.
# ------------------------------------------------------------
check_obs_writers_firing() {
  local live_home="$1" repo_root="$2"
  local ledger="${live_home}/state/signal-ledger.jsonl"

  if [[ ! -f "$ledger" ]]; then
    _warn "obs-writers-firing" "signal ledger not found at ${ledger} — observability pipeline not yet installed/run on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local now_epoch mtime_epoch age_hours
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)
  mtime_epoch=$(stat -c %Y "$ledger" 2>/dev/null || stat -f %m "$ledger" 2>/dev/null || echo 0)
  age_hours=$(( (now_epoch - mtime_epoch) / 3600 ))

  if [[ "$age_hours" -gt 24 ]]; then
    _red "obs-writers-firing" "signal ledger ${ledger} has not been written to in ${age_hours}h (budget 24h) — every ledger writer may have silently stopped firing; check session-start-digest.sh/stop-verdict-dispatcher.sh/workstreams-stop-writer.sh wiring"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local line_count
  line_count=$(wc -l < "$ledger" 2>/dev/null | tr -d ' ')
  [[ -n "$line_count" ]] || line_count=0

  local stamp_dir="${live_home}/state/doctor-cache"
  local stamp_file="${stamp_dir}/obs-ledger-stamp.txt"
  mkdir -p "$stamp_dir" 2>/dev/null || true

  if [[ ! -f "$stamp_file" ]]; then
    printf '%s %s\n' "$mtime_epoch" "$line_count" > "$stamp_file" 2>/dev/null || true
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local prev_mtime prev_lines
  read -r prev_mtime prev_lines < "$stamp_file" 2>/dev/null
  prev_mtime="${prev_mtime:-0}"
  prev_lines="${prev_lines:-0}"

  if [[ "$mtime_epoch" -le "$prev_mtime" || "$line_count" -le "$prev_lines" ]]; then
    _red "obs-writers-firing" "signal ledger ${ledger} has NOT grown since the last doctor check (was ${prev_lines} lines at mtime ${prev_mtime}, now ${line_count} lines at mtime ${mtime_epoch}) despite being <24h old — writers may be looping without emitting, or the file was truncated/rotated without the rotation being reflected here"
  fi

  printf '%s %s\n' "$mtime_epoch" "$line_count" > "$stamp_file" 2>/dev/null || true
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: obs-heartbeats-fresh (specs-o §O.6 item 2, re-fixed 2026-07-06 —
# see "CANONICAL-ORACLE FIX" below). Every session with a transcript
# mtime <30min must have a heartbeat file that is NOT classified `missing`
# by the canonical read-side oracle (else RED naming the missing sids).
# Zero live sessions is GREEN.
#
# ORCHESTRATOR FIX (found running this predicate's own self-test
# scenarios against the full suite, batch 2): the fragment's original
# default fell back to "${HOME}/.claude/projects" — the REAL machine's
# transcript tree — rather than deriving from $live_home (which every
# self-test scenario already sandboxes via HARNESS_DOCTOR_HOME). That
# leaked this machine's real live sessions into EVERY OTHER unrelated
# doctor self-test scenario that doesn't explicitly set
# OBS_TRANSCRIPTS_DIR, RED-ing them all with "N session(s) ... no
# heartbeat directory". Default now derives from $live_home
# (${live_home}/projects, i.e. $HOME/.claude/projects when live_home is
# the real $HOME/.claude — see resolve_live_home) so a sandboxed
# HARNESS_DOCTOR_HOME automatically isolates transcripts too; explicit
# OBS_TRANSCRIPTS_DIR still overrides for fixtures that want a flat
# (non-nested) layout.
#
# CANONICAL-ORACLE FIX (O.6 re-verifier round, FAIL conf 9 —
# duplicated-staleness-oracle / mid-turn false-stall): this predicate used
# to re-implement its OWN raw heartbeat-file-mtime staleness math (an
# equal 30/30-minute window against the heartbeat file's mtime alone).
# That duplicated (and silently diverged from) the canonical read-side
# oracle in hooks/lib/session-heartbeat-lib.sh (`hb_classify`/
# `hb_is_stale`), which already carries the C1 transcript-mtime join: a
# long, tool-heavy turn produces no NEW heartbeat write for its entire
# duration (heartbeats only refresh at Stop), so a session whose current
# turn simply runs past 30 minutes has a stale-BY-MTIME heartbeat file
# while being demonstrably alive (its transcript is still being appended
# to). The old raw-mtime math could not see that and false-REDed the
# session's own heartbeat mid-turn. Fixed by sourcing the canonical lib
# and reusing `hb_classify` instead of re-deriving staleness locally —
# per CANONICAL-COUNTERS-01, two implementations of "is this heartbeat
# stale" drifting apart is exactly the bug class this predicate must not
# reintroduce. RED now fires ONLY on `missing` (the genuine
# writer-not-wired signal: no heartbeat file exists at all for a session
# with a fresh transcript) — a PRESENT-but-stale-by-mtime heartbeat
# resolves through the lib's own transcript-mtime join and is classified
# `live` (or, if genuinely stalled/crashed by the lib's own pid check,
# `stale`/`crashed` — neither of which this doctor predicate treats as a
# writer-wiring failure; only `missing` is).
# ------------------------------------------------------------
check_obs_heartbeats_fresh() {
  local live_home="$1" repo_root="$2"
  local hb_dir="${live_home}/state/heartbeats"
  local transcripts_dir="${OBS_TRANSCRIPTS_DIR:-${live_home}/projects}"

  if [[ ! -d "$transcripts_dir" ]]; then
    _warn "obs-heartbeats-fresh" "no transcripts directory at ${transcripts_dir} — nothing to check (zero live sessions)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local now_epoch
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)

  local -a live_sids=()
  local f mtime age_min sid
  # ORCHESTRATOR FIX (verifier-round FAIL, O.6 conf 9): a session's
  # subagent transcripts live under <sid>/subagents/*.jsonl (and future
  # workflow sub-transcripts under <sid>/workflows/*.jsonl) — these are
  # NOT independent sessions and never write their own heartbeat file
  # (only the top-level session heartbeat writer runs), so counting them
  # as "sessions requiring a heartbeat" false-REDs this check on any
  # estate with recent agent/subagent activity, which is the common case.
  # Exclude both path shapes from enumeration entirely.
  while IFS= read -r -d '' f; do
    case "$f" in
      */subagents/*|*/workflows/*) continue ;;
    esac
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    age_min=$(( (now_epoch - mtime) / 60 ))
    if [[ "$age_min" -lt 30 ]]; then
      sid="$(basename "$f" .jsonl)"
      live_sids+=("$sid")
    fi
  done < <(find "$transcripts_dir" -type f -name '*.jsonl' -print0 2>/dev/null)

  if [[ "${#live_sids[@]}" -eq 0 ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  if [[ ! -d "$hb_dir" ]]; then
    _red "obs-heartbeats-fresh" "${#live_sids[@]} session(s) have a transcript <30min old but no heartbeat directory exists at ${hb_dir} — session-heartbeat.sh touch is not wired or O.2 is not installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # Source the canonical read-side oracle (hb_classify/hb_is_stale) once.
  # Guarded by the lib's own source-guard (_SESSION_HEARTBEAT_LIB_SOURCED),
  # so re-sourcing across repeated check invocations in the same process
  # is a safe no-op.
  local hb_lib="${SCRIPT_DIR}/lib/session-heartbeat-lib.sh"
  if [[ -f "$hb_lib" ]]; then
    # shellcheck disable=SC1090
    source "$hb_lib"
  fi

  local -a stale_sids=()
  for sid in "${live_sids[@]}"; do
    local hbf="${hb_dir}/${sid}.json"
    if ! command -v hb_classify >/dev/null 2>&1; then
      # Canonical lib unavailable (should not happen on an installed
      # estate) — degrade to the one check we CAN still make honestly:
      # file presence. Never re-derive mtime staleness locally here again.
      if [[ ! -f "$hbf" ]]; then
        stale_sids+=("${sid}:missing")
      fi
      continue
    fi
    # HEARTBEAT_STATE_DIR / OBS_TRANSCRIPTS_ROOT bridge this doctor
    # predicate's own sandboxing vars (HARNESS_DOCTOR_HOME-derived
    # $hb_dir / $transcripts_dir) into the lib's env-var contract so its
    # transcript-mtime join (_hb_find_transcript) looks in the SAME
    # sandboxed fixture tree this check just enumerated, not the real
    # machine's $HOME/.claude estate.
    local cls
    cls="$(HEARTBEAT_STATE_DIR="$hb_dir" OBS_TRANSCRIPTS_ROOT="$transcripts_dir" hb_classify "$hbf" 30)"
    if [[ "$cls" == "missing" ]]; then
      stale_sids+=("${sid}:missing")
    fi
  done

  if [[ "${#stale_sids[@]}" -gt 0 ]]; then
    _red "obs-heartbeats-fresh" "$(IFS=,; echo "${stale_sids[*]}") — session(s) with a transcript <30min old have NO heartbeat file at all; the heartbeat writer may not be wired into this session's chain (see tests/fixtures/wave-o/O.2/callsite-wiring.md)"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: obs-scheduled-tasks (specs-o §O.6 item 3, SCHEDULED-TASK-HEALTH-01).
# Every registered NL-owned task (via scripts/scheduled-task-health.sh
# list) has Last Result in {0, 267009, 267011}; else RED naming the task +
# code. Not-registered stays the existing WARN semantics elsewhere.
# ------------------------------------------------------------
check_obs_scheduled_tasks() {
  local live_home="$1" repo_root="$2"
  local script=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/scripts/scheduled-task-health.sh" ]] \
    && script="${repo_root}/adapters/claude-code/scripts/scheduled-task-health.sh"
  [[ -z "$script" && -f "${live_home}/scripts/scheduled-task-health.sh" ]] \
    && script="${live_home}/scripts/scheduled-task-health.sh"

  if [[ -z "$script" ]]; then
    _warn "obs-scheduled-tasks" "scheduled-task-health.sh missing — O.6 not yet installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v schtasks >/dev/null 2>&1 && [[ -z "${SCHTASKS_CMD:-}" ]]; then
    _warn "obs-scheduled-tasks" "schtasks not available on this platform — scheduled-task health check skipped (non-Windows)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out
  out="$(bash "$script" list 2>/dev/null)"
  if [[ -z "$out" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local line name code bad=0
  while IFS=$'\t' read -r name code; do
    [[ -z "$name" ]] && continue
    case "$code" in
      0|267009|267011) ;;
      *)
        _red "obs-scheduled-tasks" "task '${name}' Last Result=${code} (expected one of 0/267009/267011) — check the task's registered command path; run: MSYS_NO_PATHCONV=1 schtasks /Query /V /FO LIST /TN \"${name}\""
        bad=1
        ;;
    esac
  done <<< "$out"

  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: obs-consumer-map (specs-o §O.6 item 4, contract C3's enforcing
# predicate). Two-sided: (a) every event type observed in the ledger's
# last 1000 lines has an entry in observability-consumer-map.json; (b)
# every literal event-type string passed as the SECOND argument to
# ledger_emit/ledger_emit_typed anywhere in the repo has an entry; (c)
# every entry in the map has >=1 consumer. Unknown-in-map = RED naming
# the type. The literal-scan filters out variable-named 2nd-args
# (grep -vE '^\$') — several real pre-existing call sites
# (stop-verdict-dispatcher.sh, work-integrity-gate.sh, session-resumer.sh,
# test-gate.sh's own self-test) pass a variable, not a literal, as the
# 2nd arg; without the filter this predicate would RED on bogus
# "unmapped event type '$ev'" noise. CRLF: `tr -d '\r'` on the ledger-side
# jq output is required — this machine's real ledger round-trips through
# jq with CRLF line endings (findings 030/038-class).
# ------------------------------------------------------------
check_obs_consumer_map() {
  local live_home="$1" repo_root="$2"
  local map=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/observability-consumer-map.json" ]] \
    && map="${repo_root}/adapters/claude-code/observability-consumer-map.json"
  [[ -z "$map" && -f "${live_home}/observability-consumer-map.json" ]] \
    && map="${live_home}/observability-consumer-map.json"

  if [[ -z "$map" ]]; then
    _warn "obs-consumer-map" "observability-consumer-map.json not found — O.1 not yet installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _warn "obs-consumer-map" "jq not available — cannot verify observability-consumer-map.json coverage"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! jq -e . "$map" >/dev/null 2>&1; then
    _red "obs-consumer-map" "${map} is not valid JSON"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # (c) every map entry has >=1 consumer
  local empty_entries
  empty_entries="$(jq -r '.event_types | to_entries[] | select((.value.consumers // []) | length == 0) | .key' "$map" 2>/dev/null)"
  if [[ -n "$empty_entries" ]]; then
    _red "obs-consumer-map" "event type(s) with zero consumers in ${map}: $(printf '%s' "$empty_entries" | tr '\n' ',' | sed 's/,$//')"
  fi

  # (a) every ledger-observed event type (last 1000 lines) is in the map.
  local ledger="${live_home}/state/signal-ledger.jsonl"
  if [[ -f "$ledger" ]]; then
    local unmapped_ledger
    unmapped_ledger="$(tail -n 1000 "$ledger" 2>/dev/null | jq -r '.event // empty' 2>/dev/null | tr -d '\r' | sort -u | while read -r ev; do
      [[ -z "$ev" ]] && continue
      jq -e --arg e "$ev" '.event_types | has($e)' "$map" >/dev/null 2>&1 || echo "$ev"
    done)"
    if [[ -n "$unmapped_ledger" ]]; then
      _red "obs-consumer-map" "ledger event type(s) observed in last 1000 lines but absent from ${map}: $(printf '%s' "$unmapped_ledger" | tr '\n' ',' | sed 's/,$//')"
    fi
  fi

  # (b) every literal ledger_emit(_typed) 2nd-arg literal in the repo is in
  # the map. grep -vE '^\$' filters variable-named 2nd-args (see header
  # comment above).
  if [[ -n "$repo_root" ]]; then
    local unmapped_repo
    unmapped_repo="$(grep -rhoE 'ledger_emit(_typed)?[[:space:]]+"[^"]*"[[:space:]]+"[^"]*"' \
        "${repo_root}/adapters/claude-code/hooks" "${repo_root}/adapters/claude-code/scripts" 2>/dev/null \
      | sed -E 's/ledger_emit(_typed)?[[:space:]]+"[^"]*"[[:space:]]+"([^"]*)"/\2/' \
      | grep -vE '^\$' \
      | sort -u | while read -r ev; do
        [[ -z "$ev" ]] && continue
        jq -e --arg e "$ev" '.event_types | has($e)' "$map" >/dev/null 2>&1 || echo "$ev"
      done)"
    if [[ -n "$unmapped_repo" ]]; then
      _red "obs-consumer-map" "literal ledger_emit event type(s) found in repo source but absent from ${map}: $(printf '%s' "$unmapped_repo" | tr '\n' ',' | sed 's/,$//')"
    fi
  fi

  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: obs-cockpit-fresh (specs-o §O.6 item 5). WARN-only, never RED
# (per specs-o §O.6 exactly). GREEN when the cockpit is intentionally not
# running (optional per machine). Fires only when NL-workstreams-cockpit
# is registered for autostart AND sessions are live AND the derived-cache
# stamp is >60min stale.
# ------------------------------------------------------------
check_obs_cockpit_fresh() {
  local live_home="$1" repo_root="$2"
  local cockpit_dir=""
  [[ -n "$repo_root" && -d "${repo_root}/workstreams-ui/server" ]] \
    && cockpit_dir="${repo_root}/workstreams-ui/server"

  if [[ -z "$cockpit_dir" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local registered=0
  if command -v schtasks >/dev/null 2>&1; then
    MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-workstreams-cockpit" >/dev/null 2>&1 && registered=1
  fi
  if [[ "$registered" -eq 0 ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local hb_dir="${live_home}/state/heartbeats"
  local now_epoch any_live=0
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)
  if [[ -d "$hb_dir" ]]; then
    local f mtime age_min
    while IFS= read -r -d '' f; do
      mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
      age_min=$(( (now_epoch - mtime) / 60 ))
      [[ "$age_min" -lt 30 ]] && any_live=1
    done < <(find "$hb_dir" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)
  fi
  if [[ "$any_live" -eq 0 ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local stamp="${live_home}/state/workstreams-cache/derived-cache-stamp.txt"
  if [[ ! -f "$stamp" ]]; then
    _warn "obs-cockpit-fresh" "cockpit registered for autostart (NL-workstreams-cockpit) and sessions are live, but no derived-cache stamp found at ${stamp} — cockpit server may not be running or has never refreshed"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local stamp_mtime stamp_age_min
  stamp_mtime=$(stat -c %Y "$stamp" 2>/dev/null || stat -f %m "$stamp" 2>/dev/null || echo 0)
  stamp_age_min=$(( (now_epoch - stamp_mtime) / 60 ))
  if [[ "$stamp_age_min" -gt 60 ]]; then
    _warn "obs-cockpit-fresh" "cockpit derived-cache stamp is ${stamp_age_min}min old (budget 60min) while sessions are live and autostart is registered — cockpit may be stalled; check workstreams-ui/server process"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: needs-you-headers (specs-o §O.6 item 6, E6-HEADER-HARDENING-01).
# When the needs-you ledger's open decision-count is >0, NEEDS-YOU.md
# must contain all 4 NY_CANONICAL_HEADERS. Gated on ny_open>0, same
# posture as the existing E.6 staleness check in check_wave_e_surfaces.
# ------------------------------------------------------------
check_needs_you_headers() {
  local live_home="$1" repo_root="$2"

  local ny_nlpaths="${repo_root}/adapters/claude-code/hooks/lib/nl-paths.sh"
  local ny_main_root=""
  [[ -f "$ny_nlpaths" ]] && ny_main_root=$(bash -c "source '$ny_nlpaths'; nl_main_checkout_root" 2>/dev/null)
  [[ -n "$ny_main_root" ]] || ny_main_root="$repo_root"
  local ny_md="${ny_main_root}/NEEDS-YOU.md"
  local ny_state="${live_home}/state/needs-you/ledger.json"

  if [[ ! -f "$ny_state" ]]; then
    _warn "needs-you-headers" "needs-you ledger not found at ${ny_state} — E.6 not yet installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _warn "needs-you-headers" "jq not available — cannot check needs-you open-count"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local ny_open
  ny_open=$(jq '[.items[] | select(.section == "decision" and .state == "open")] | length' "$ny_state" 2>/dev/null || echo 0)
  [[ "${ny_open:-0}" -gt 0 ]] || { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  if [[ ! -f "$ny_md" ]]; then
    _red "needs-you-headers" "NEEDS-YOU.md missing at ${ny_md} despite ${ny_open} open decision item(s) — run: bash adapters/claude-code/scripts/needs-you.sh render"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local -a headers=(
    "## Awaiting your decision"
    "## Open questions"
    "## In flight (sessions + waves)"
    "## Recently decided for your §8 review"
  )
  local -a missing=()
  local h
  for h in "${headers[@]}"; do
    grep -qF "$h" "$ny_md" 2>/dev/null || missing+=("$h")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    _red "needs-you-headers" "NEEDS-YOU.md (${ny_md}) missing $(printf '%s' "${#missing[@]}") of 4 canonical header(s) despite ${ny_open} open decision item(s): $(IFS='|'; echo "${missing[*]}") — run: bash adapters/claude-code/scripts/needs-you.sh render"
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
#
# Blocking gates <= 12. COUNTING RULE (Wave-F integration fix, 2026-07-06):
# this budget was FROZEN at Wave D as specs-d §D.0.4's "blocking session-event
# UNITS" definition — manifest entries with blocking:true AND wired_template:
# true AND wired to a live-session event (Stop/PreToolUse/SessionStart/
# PostToolUse/UserPromptSubmit/TaskCreated/TaskCompleted), with same-class
# entries CONSOLIDATED into one unit (e.g. env-local-protection +
# deploy-automation-mode = one "command-safety" unit; the 5 commit-time-only
# gates = one "commit-boundary" unit). git-boundary hooks (precommit/prepush)
# are an explicitly SEPARATE budget class, not counted here. D.5's evidence
# block ("blocking budget 12/12 GREEN") was produced by exactly this counting
# method via scripts/blocking-budget-check.js — that script is kept as the
# SOLE implementation (avoid a second, drifting reimplementation here); this
# check shells out to it.
#
# An earlier version of this check counted every manifest entry with bare
# blocking:true (no wired_template/live-event filter, no consolidation),
# which conflates the D.0.4 budget with a raw entry count and inflates the
# reported number well past 12 for reasons the budget was never meant to
# flag (git-boundary-only gates, GAP entries not yet wired live, and
# same-class hooks the frozen rule explicitly treats as one unit). Fixed
# during Wave-F integration (F.1+F.5+F.2 merge) rather than relaxing the
# budget number itself — the true post-Wave-D-and-E number, by the correct
# definition, is 10/12 (GREEN, 2 units of headroom).
# ------------------------------------------------------------
check_budget_blocking_gates() {
  local live_home="$1" repo_root="$2"
  local manifest
  if ! manifest="$(resolve_manifest "$live_home" "$repo_root")"; then
    _warn "budget-blocking-gates" "no manifest.json found (live mirror or repo) — skipped (pre-C.1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    _warn "budget-blocking-gates" "node not available — blocking-budget-check.js requires node — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local checker="${repo_root}/adapters/claude-code/scripts/blocking-budget-check.js"
  [[ -f "$checker" ]] || checker="${live_home}/scripts/blocking-budget-check.js"
  if [[ ! -f "$checker" ]]; then
    _warn "budget-blocking-gates" "manifest.json present but blocking-budget-check.js not found (repo scripts/ or live scripts/) — cannot validate"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out rc
  out="$(node "$checker" "$manifest" 2>&1)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    local units_line
    units_line="$(printf '%s\n' "$out" | grep -m1 'blocking session-event units:' || true)"
    _red "budget-blocking-gates" "${units_line:-blocking-budget-check.js reported over-budget} (budget <= 12 consolidated units per specs-d §D.0.4) — ${manifest}; remediation: demote via scripts/gate-demotion.sh (F.5) or consolidate per ADR 059 D7"
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

  # De-dup by GIT IDENTITY, not raw path string. When the doctor runs from a
  # linked worktree, resolve_repo_root()'s own root (this worktree's
  # toplevel) and <live_home>/local/nl-repo-path (the main checkout) are two
  # DIFFERENT absolute paths that are nonetheless the SAME repository —
  # `git worktree` gives every linked worktree its own toplevel but they all
  # share one `git rev-parse --git-common-dir` (the shared .git). A raw
  # `sort -u` on path strings does not catch this and double-counts every
  # plan in docs/plans/ once per worktree that resolves to the same repo
  # (verifier live-probe: "6 across 2 roots" vs true 3, both roots worktrees
  # of one repo). Fix: key de-dup on each root's resolved git-common-dir
  # (falling back to the raw path itself for non-git roots, e.g. the live
  # mirror tier or a future non-repo project-roots entry) so two worktrees
  # of one repo collapse to a single counted root. Linear scan (not
  # associative arrays — this file targets bash 3.2 for macOS parity) over
  # a handful of roots; first-seen root per key wins, preserving the
  # documented priority order (repo_root, then nl-repo-path, then
  # nl-project-roots).
  local -a seen_keys=() out=()
  local r key already
  for r in "${roots[@]}"; do
    [[ -z "$r" ]] && continue
    key=""
    if [[ -d "$r" ]] && command -v git >/dev/null 2>&1; then
      key="$(git -C "$r" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
      # Older git (pre-2.31) lacks --path-format; fall back to the raw
      # (possibly relative) --git-common-dir and normalize it against $r.
      if [[ -z "$key" ]]; then
        local raw_gcd
        raw_gcd="$(git -C "$r" rev-parse --git-common-dir 2>/dev/null)"
        if [[ -n "$raw_gcd" ]]; then
          case "$raw_gcd" in
            /*) key="$raw_gcd" ;;
            *) key="${r}/${raw_gcd}" ;;
          esac
        fi
      fi
    fi
    [[ -z "$key" ]] && key="$r"

    already=0
    local sk
    for sk in "${seen_keys[@]+"${seen_keys[@]}"}"; do
      [[ "$sk" == "$key" ]] && { already=1; break; }
    done
    if [[ "$already" -eq 0 ]]; then
      seen_keys+=("$key")
      out+=("$r")
    fi
  done

  [[ "${#out[@]}" -eq 0 ]] && return 0
  printf '%s\n' "${out[@]}"
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
# Check: line-endings (NL-FINDING-038, Wave-F F.1 incident; live-mirror scan
# added for LIVE-MIRROR-CRLF-01). On Windows a file-edit can silently
# rewrite a whole tracked script LF -> CRLF: before .gitattributes landed
# that produced a ~2000-line spurious diff; with the eol=lf pin in force
# the clean filter NORMALIZES the comparison instead, so `git status` shows
# CLEAN while the on-disk bytes stay CRLF — invisible to git, but
# install.sh cp's those working-tree bytes live, Linux CI bash hard-fails
# on \r, and heredocs the script emits carry the pollution forward. This
# check is the primary detector for that masked state in the REPO working
# tree.
#
# The live mirror (~/.claude) is ALSO scanned now, but only ever WARNs
# (never REDs): a mirror built before the .gitattributes pin landed, or by
# an installer running on a stale core.autocrlf=true checkout, can carry
# CRLF forward via install.sh's `cp` fallback (no symlink support) even
# though the repo tree is clean today. That is stale-mirror drift, not an
# active break — MSYS bash tolerates CRLF at runtime — and install.sh's
# CRLF-normalization-on-copy (LIVE-MIRROR-CRLF-01) self-heals it on the next
# run, so RED would be a false alarm for a one-command fix. Distinguishing
# it from a real REPO regression (still RED) is exactly the fix this
# extension delivers — NL-FINDING-038's own residual-risk note flagged that
# the doctor "is the only detector" of masked CRLF yet never looked at the
# one place (the live mirror) that matters at runtime.
# Detection is pure-bash byte matching ([[ == *$'\r'* ]]) — NEVER grep/sed/
# awk, which silently strip \r on MSYS (NL-FINDING-030).
#   RED  : a tracked shell surface (*.sh, git-hooks/*) has CR bytes on disk
#          in the REPO working tree.
#   WARN : repo .gitattributes lacks the '*.sh text eol=lf' pin, OR the live
#          mirror (~/.claude/hooks, hooks/lib, scripts) carries CRLF while
#          the repo tree is clean (transition-period signal — run
#          install.sh to normalize; never RED for this half of the check).
# ------------------------------------------------------------
check_line_endings() {
  local live_home="$1" repo_root="$2"
  if [[ -z "$repo_root" ]]; then
    _warn "line-endings" "repo root unresolved — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local f content toplevel
  toplevel="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$toplevel" && "$toplevel" -ef "$repo_root" ]]; then
    # Real repo (repo_root IS the toplevel — an -ef inode compare, so a
    # fixture dir that merely sits INSIDE some repo still takes the glob
    # branch): enumerate every tracked shell surface.
    # process-substitution (not a trailing pipe) so _red's RED_COUNT
    # increment happens in THIS shell (same trap as lib-deps).
    while IFS= read -r -d '' f; do
      [[ -f "$repo_root/$f" && -s "$repo_root/$f" ]] || continue
      content="$(<"$repo_root/$f")"
      if [[ "$content" == *$'\r'* ]]; then
        _red "line-endings" "${f} has CR bytes in the working tree (the eol=lf clean filter masks this — git status shows clean) — fix: dos2unix '${f}' (NL-FINDING-038)"
      fi
    done < <(git -C "$repo_root" ls-files -z -- '*.sh' 'adapters/claude-code/git-hooks/*' 2>/dev/null)
  else
    # Non-git contexts (self-test fixtures): scan the adapter shell dirs.
    for f in "$repo_root"/adapters/claude-code/hooks/*.sh \
             "$repo_root"/adapters/claude-code/hooks/lib/*.sh \
             "$repo_root"/adapters/claude-code/scripts/*.sh \
             "$repo_root"/adapters/claude-code/git-hooks/*; do
      [[ -f "$f" && -s "$f" ]] || continue
      content="$(<"$f")"
      if [[ "$content" == *$'\r'* ]]; then
        _red "line-endings" "${f#"$repo_root"/} has CR bytes — fix: dos2unix (NL-FINDING-038)"
      fi
    done
  fi

  if [[ ! -f "$repo_root/.gitattributes" ]] \
     || ! grep -qE '^\*\.sh[[:space:]]+text[[:space:]]+eol=lf' "$repo_root/.gitattributes" 2>/dev/null; then
    _warn "line-endings" ".gitattributes is missing its '*.sh text eol=lf' pin — CRLF can enter the index on clones without a local autocrlf override (NL-FINDING-038)"
  fi

  # Live-mirror scan (LIVE-MIRROR-CRLF-01): WARN-only, transition-period
  # signal. Scans ${live_home}/hooks/*.sh, ${live_home}/hooks/lib/*.sh, and
  # ${live_home}/scripts/*.sh for CR bytes using the same pure-bash byte
  # match as the repo scan above (never grep — NL-FINDING-030). A single
  # WARN covers the whole mirror (not one per file) so a stale mirror
  # doesn't flood the doctor's output; the fix (re-run install.sh) is the
  # same regardless of how many files carry CRLF.
  if [[ -n "$live_home" && -d "$live_home" ]]; then
    local live_crlf_found=0
    for f in "$live_home"/hooks/*.sh \
             "$live_home"/hooks/lib/*.sh \
             "$live_home"/scripts/*.sh; do
      [[ -f "$f" && -s "$f" ]] || continue
      content="$(<"$f")"
      if [[ "$content" == *$'\r'* ]]; then
        live_crlf_found=1
        break
      fi
    done
    if [[ "$live_crlf_found" -eq 1 ]]; then
      _warn "line-endings" "live mirror carries pre-pin CRLF — run install.sh to normalize (${live_home}/hooks and/or scripts contain CR bytes; NL-FINDING-038 residual-risk gap, LIVE-MIRROR-CRLF-01)"
    fi
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
  check_wave_f_f2_docs "$live_home" "$repo_root"
  check_wave_e_surfaces "$live_home" "$repo_root"
  check_heartbeat_task "$live_home" "$repo_root"
  check_untracked_dirt_ignore_rule "$live_home" "$repo_root"
  # NL Observability Program Wave O, task O.6 (specs-o §O.6) — pipeline
  # health predicates, spliced batch 2.
  check_obs_writers_firing "$live_home" "$repo_root"
  check_obs_heartbeats_fresh "$live_home" "$repo_root"
  check_obs_scheduled_tasks "$live_home" "$repo_root"
  check_obs_consumer_map "$live_home" "$repo_root"
  check_obs_cockpit_fresh "$live_home" "$repo_root"
  check_needs_you_headers "$live_home" "$repo_root"
  check_pin_f_waiver_purpose_clauses "$live_home" "$repo_root"
  check_line_endings "$live_home" "$repo_root"
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
    # E.6 fixture stamp (NL-FINDING-039): check_wave_e_e6_needs_you REDs when
    # the repo-side needs-you.sh is missing / non-executable / lacking a
    # --self-test entrypoint. The NL-FINDING-035 round-2 fix added that
    # predicate without stamping the fixtures, breaking every rc-0 scenario
    # in this suite. Every fixture repo gets a conforming stub.
    printf '#!/bin/bash\n# fixture stub; the real script ships via install.sh\n[[ "${1:-}" == "--self-test" ]] && exit 0\nexit 0\n' \
      > "$dir/repo/adapters/claude-code/scripts/needs-you.sh"
    chmod +x "$dir/repo/adapters/claude-code/scripts/needs-you.sh" 2>/dev/null
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
      "honesty_rationale": "fixture: waiver-parity satisfied for this manifest-check/claim-honesty fixture",
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
      "waiver_path": "fixture-waiver-*.txt",
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

  # ---- Check: wave-f-f2-docs Predicate 1 (harness-architecture.md drift).
  # RED fixture — a real gen-architecture-doc.sh copy + a hand-edited
  # committed doc that no longer matches a fresh regen from manifest.json. ----
  D=$(_scenario_dir f2p1-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/docs"
  cp "$SCRIPT_DIR/../scripts/gen-architecture-doc.sh" "$D/repo/adapters/claude-code/scripts/gen-architecture-doc.sh"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'F2MANIFEST_EOF'
{"schema_version":1,"entries":[{"id":"a","kind":"gate","hooks":["a.sh"],"events":["precommit"],"blocking":true,"selftest":true,"wired_template":true,"honest_status":"x","budget_class":"none"}]}
F2MANIFEST_EOF
  ( cd "$D/repo" && bash adapters/claude-code/scripts/gen-architecture-doc.sh >/dev/null 2>&1 )
  echo "hand-edited drift line" >> "$D/repo/docs/harness-architecture.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate1-red" 1 "$RC" "RED wave-f-f2-docs.*harness-architecture" "$OUT"

  # ---- Check: wave-f-f2-docs Predicate 1 GREEN fixture — committed doc
  # freshly regenerated, byte-identical to a re-run ----
  D=$(_scenario_dir f2p1-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/docs"
  cp "$SCRIPT_DIR/../scripts/gen-architecture-doc.sh" "$D/repo/adapters/claude-code/scripts/gen-architecture-doc.sh"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'F2MANIFEST_EOF'
{"schema_version":1,"entries":[{"id":"a","kind":"gate","hooks":["a.sh"],"events":["precommit"],"blocking":true,"selftest":true,"wired_template":true,"honest_status":"x","budget_class":"none"}]}
F2MANIFEST_EOF
  ( cd "$D/repo" && bash adapters/claude-code/scripts/gen-architecture-doc.sh >/dev/null 2>&1 )
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate1-green" 0 "$RC" "" "$OUT"

  # ---- Check: wave-f-f2-docs Predicate 2 (README freshness anchors). RED
  # fixture — one of the five surfaces has a 100-day-old anchor, the rest
  # fresh (today). Uses backdated `date` arithmetic, not a hardcoded
  # calendar date, so this fixture never goes stale itself. ----
  D=$(_scenario_dir f2p2-red)
  _stamp_claim_honesty_green "$D"
  _f2_today="$(date +%Y-%m-%d)"
  _f2_stale_date="$(date -d '-100 days' +%Y-%m-%d 2>/dev/null || date -j -v-100d +%Y-%m-%d 2>/dev/null)"
  mkdir -p "$D/repo/adapters/claude-code/attic" "$D/repo/evals" "$D/repo/neural-lace/workstreams-ui"
  printf '# Repo\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today" > "$D/repo/README.md"
  printf '# Adapter\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today" > "$D/repo/adapters/claude-code/README.md"
  printf '# Attic\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_stale_date" > "$D/repo/adapters/claude-code/attic/README.md"
  printf '# Evals\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today" > "$D/repo/evals/README.md"
  printf '# UI\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today" > "$D/repo/neural-lace/workstreams-ui/README.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate2-stale-red" 1 "$RC" "RED wave-f-f2-docs.*STALE.*attic/README.md" "$OUT"

  # ---- Check: wave-f-f2-docs Predicate 2 RED fixture — one surface
  # missing its anchor entirely ----
  D=$(_scenario_dir f2p2-noanchor-red)
  _stamp_claim_honesty_green "$D"
  _f2_today2="$(date +%Y-%m-%d)"
  mkdir -p "$D/repo/adapters/claude-code/attic" "$D/repo/evals" "$D/repo/neural-lace/workstreams-ui"
  printf '# Repo\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today2" > "$D/repo/README.md"
  printf '# Adapter\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today2" > "$D/repo/adapters/claude-code/README.md"
  printf '# Attic (no anchor)\n' > "$D/repo/adapters/claude-code/attic/README.md"
  printf '# Evals\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today2" > "$D/repo/evals/README.md"
  printf '# UI\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today2" > "$D/repo/neural-lace/workstreams-ui/README.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate2-noanchor-red" 1 "$RC" "RED wave-f-f2-docs.*NO-ANCHOR.*attic/README.md" "$OUT"

  # ---- Check: wave-f-f2-docs Predicate 2 GREEN fixture — all five anchors
  # present and fresh (today) ----
  D=$(_scenario_dir f2p2-green)
  _stamp_claim_honesty_green "$D"
  _f2_today3="$(date +%Y-%m-%d)"
  mkdir -p "$D/repo/adapters/claude-code/attic" "$D/repo/evals" "$D/repo/neural-lace/workstreams-ui"
  printf '# Repo\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/README.md"
  printf '# Adapter\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/adapters/claude-code/README.md"
  printf '# Attic\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/adapters/claude-code/attic/README.md"
  printf '# Evals\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/evals/README.md"
  printf '# UI\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/neural-lace/workstreams-ui/README.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate2-green" 0 "$RC" "" "$OUT"

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

  # ---- Check: budget-blocking-gates. Counting rule (specs-d §D.0.4, fixed
  # during Wave-F integration): blocking:true AND wired_template:true AND
  # wired to a live-session event, with same-class consolidation via
  # blocking-budget-check.js's UNIT_MAP — NOT a bare blocking:true count.
  # Fixture entries must be wired_template:true with a session event
  # (PreToolUse here) to be counted at all; each fixture id is distinct so
  # none of them hit the UNIT_MAP consolidation table (that table's own
  # behavior is exercised live against the real manifest, not re-tested
  # here — this fixture only needs to prove the RED/GREEN threshold at 12).
  _write_blocking_manifest_fixture() {
    local dir="$1" count="$2"
    local entries="" i
    for ((i = 0; i < count; i++)); do
      [[ -n "$entries" ]] && entries="${entries},"
      entries="${entries}{\"id\":\"fixture-gate-${i}\",\"kind\":\"gate\",\"doctrine_file\":null,\"hooks\":[],\"events\":[\"PreToolUse\"],\"wired_template\":true,\"selftest\":false,\"jit_triggers\":{\"paths\":[],\"keywords\":[]},\"blocking\":true,\"honest_status\":\"fixture stub\",\"budget_class\":\"pretool\"}"
    done
    printf '{"schema_version":1,"entries":[%s]}' "$entries" > "$dir/repo/adapters/claude-code/manifest.json"
  }
  _copy_blocking_budget_tooling() {
    local dir="$1"
    local src="$SCRIPT_DIR/../scripts/blocking-budget-check.js"
    [[ -f "$src" ]] || return 1
    mkdir -p "$dir/repo/adapters/claude-code/scripts"
    cp "$src" "$dir/repo/adapters/claude-code/scripts/blocking-budget-check.js"
    return 0
  }
  D=$(_scenario_dir bbg-red)
  _stamp_claim_honesty_green "$D"
  _write_blocking_manifest_fixture "$D" 13
  _copy_blocking_budget_tooling "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-blocking-gates-red" 1 "$RC" "RED budget-blocking-gates.*blocking session-event units: 13" "$OUT"

  # ---- Check: budget-blocking-gates GREEN fixture — 12 units (at budget) ----
  D=$(_scenario_dir bbg-green)
  _stamp_claim_honesty_green "$D"
  _write_blocking_manifest_fixture "$D" 12
  _copy_blocking_budget_tooling "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-blocking-gates-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-blocking-gates — a blocking:true entry that is NOT
  # wired_template (a GAP entry) or fires only on a git-boundary event must
  # NOT count toward the budget (proves the fix: this used to inflate the
  # count under the old bare-blocking:true method). 13 non-counting entries
  # + the budget-class fixture at exactly 12 counting entries -> still GREEN.
  D=$(_scenario_dir bbg-noncounting-green)
  _stamp_claim_honesty_green "$D"
  _write_blocking_manifest_fixture "$D" 12
  node -e '
const fs = require("fs");
const p = process.argv[1];
const m = JSON.parse(fs.readFileSync(p, "utf8"));
for (let i = 0; i < 13; i++) {
  m.entries.push({ id: `fixture-noncounting-${i}`, kind: "gate", doctrine_file: null, hooks: [], events: ["precommit"], wired_template: false, selftest: false, jit_triggers: { paths: [], keywords: [] }, blocking: true, honest_status: "fixture: git-boundary, not wired live", budget_class: "none" });
}
fs.writeFileSync(p, JSON.stringify(m));
' "$D/repo/adapters/claude-code/manifest.json"
  _copy_blocking_budget_tooling "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-blocking-gates-noncounting-entries-green" 0 "$RC" "" "$OUT"

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

  # ---- Check: budget-active-plans WORKTREE DOUBLE-COUNT fixture (verifier
  # live-probe finding: doctor run from a linked worktree double-counts
  # ACTIVE plans because repo_root and <live_home>/local/nl-repo-path
  # resolve to two different absolute paths for the same repository) — a
  # real git repo with a real LINKED WORKTREE of itself, registered via
  # `git worktree add`. repo_root is pointed at the worktree; live/local/
  # nl-repo-path points at the main repo — the exact shape a doctor run
  # FROM a linked worktree produces (resolve_repo_root() resolves the
  # worktree's own toplevel; nl-repo-path names the main checkout). Both
  # sides carry the SAME docs/plans/ (2 ACTIVE plans; committed to the repo
  # so the worktree checkout sees them too — `git worktree add` checks out
  # tracked files, it does not duplicate them on disk as separate content).
  # Pre-fix: naive path-string de-dup treats these as two distinct roots
  # and double-counts -> 4 total (over budget 3) -> false RED. Post-fix:
  # git-common-dir de-dup collapses them to ONE counted root -> 2 total
  # (under budget) -> GREEN. ----
  D=$(_scenario_dir bap-wt-dedup-green)
  _stamp_claim_honesty_green "$D"
  (
    cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && mkdir -p docs/plans \
      && printf '# Plan 1\nStatus: ACTIVE\n' > docs/plans/p1.md \
      && printf '# Plan 2\nStatus: ACTIVE\n' > docs/plans/p2.md \
      && git add docs/plans && git commit --quiet -m "seed plans" \
      && git worktree add --quiet -b bap-wt-dedup-green-branch "$D/linked-worktree" >/dev/null 2>&1
  ) >/dev/null 2>&1
  mkdir -p "$D/live/local"
  printf '%s\n' "$D/repo" > "$D/live/local/nl-repo-path"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  # Point repo_root (NL_REPO_ROOT / positional arg) at the LINKED worktree,
  # not $D/repo — this reproduces "doctor invoked from the worktree" while
  # nl-repo-path (above) still names the main checkout, matching the two
  # divergent-path, same-repo shape the fix targets.
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/linked-worktree" bash "$SELF_TEST_HOOK" --quick "$D/linked-worktree" 2>&1)"; RC=$?
  _assert "budget-active-plans-worktree-dedup-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-active-plans TWO GENUINELY DISTINCT REPOS still sum
  # correctly (proves the git-common-dir de-dup is not overly permissive —
  # it must NOT collapse two unrelated repos just because both happen to be
  # git repos). repo_root = repo-one (2 ACTIVE plans); nl-repo-path =
  # repo-two (2 ACTIVE plans, its own separate .git). True total = 4 (over
  # budget 3) across 2 distinct roots -> RED. ----
  D=$(_scenario_dir bap-2repos-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo-two/docs/plans"
  (
    cd "$D/repo" && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T
  ) >/dev/null 2>&1
  (
    cd "$D/repo-two" && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T
  ) >/dev/null 2>&1
  mkdir -p "$D/repo/docs/plans"
  printf '# Plan 1\nStatus: ACTIVE\n' > "$D/repo/docs/plans/p1.md"
  printf '# Plan 2\nStatus: ACTIVE\n' > "$D/repo/docs/plans/p2.md"
  printf '# Plan 1\nStatus: ACTIVE\n' > "$D/repo-two/docs/plans/p1.md"
  printf '# Plan 2\nStatus: ACTIVE\n' > "$D/repo-two/docs/plans/p2.md"
  mkdir -p "$D/live/local"
  printf '%s\n' "$D/repo-two" > "$D/live/local/nl-repo-path"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-active-plans-two-distinct-repos-red" 1 "$RC" "RED budget-active-plans.*4 plans" "$OUT"

  # ---- Check: budget-worktrees-branches. RED fixture — a real throwaway
  # git repo with a stale (8-day-old, backdated commit) local branch with
  # no upstream. This fixture targets the branch-staleness half only; the
  # worktree-age half (a real `git worktree add` with a backdated HEAD) is
  # exercised separately by the bwb-age-red/bwb-age-green fixtures below —
  # this was a previously-admitted gap (see git history) now closed. ----
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

  # ---- Check: budget-worktrees-branches WORKTREE-AGE RED fixture — a real
  # git repo with a real LINKED WORKTREE (registered via `git worktree add`,
  # not just a branch) whose HEAD commit is backdated >=7d via
  # GIT_COMMITTER_DATE. This exercises the worktree age sub-check itself
  # (the wt_path/HEAD loop over `git worktree list --porcelain` in
  # check_budget_worktrees_branches), which the pre-existing bwb-red/
  # bwb-green fixtures above admit (in their own comment) they never
  # exercised — this fixture closes that gap. ----
  D=$(_scenario_dir bwb-age-red)
  _stamp_claim_honesty_green "$D"
  (
    _bwb_age_stale_ts=$(( $(date -u +%s) - 8 * 86400 )) \
      && cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init \
      && git worktree add --quiet -b stale-worktree-branch "$D/stale-worktree" >/dev/null 2>&1 \
      && cd "$D/stale-worktree" \
      && git config core.hooksPath "" \
      && echo y > g && git add g \
      && GIT_AUTHOR_DATE="@${_bwb_age_stale_ts} +0000" GIT_COMMITTER_DATE="@${_bwb_age_stale_ts} +0000" git commit --quiet -m stale-worktree-commit
  ) >/dev/null 2>&1
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-worktrees-branches-age-red" 1 "$RC" "RED budget-worktrees-branches.*stale-worktree.*no commit in [89][0-9]*d" "$OUT"

  # ---- Check: budget-worktrees-branches WORKTREE-AGE GREEN fixture — a
  # real linked worktree with a fresh (just-made) commit; must NOT flag ----
  D=$(_scenario_dir bwb-age-green)
  _stamp_claim_honesty_green "$D"
  (
    cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init \
      && git worktree add --quiet -b fresh-worktree-branch "$D/fresh-worktree" >/dev/null 2>&1 \
      && cd "$D/fresh-worktree" \
      && git config core.hooksPath "" \
      && echo y > g && git add g && git commit --quiet -m fresh-worktree-commit
  ) >/dev/null 2>&1
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-worktrees-branches-age-green" 0 "$RC" "" "$OUT"

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
      "golden_scenario": "Downstream-product incident 2026-07-03 cross-repo write",
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

  # ---- Check: line-endings (NL-FINDING-038). RED fixture — a repo shell
  # surface carries CRLF bytes (the Wave-F F.1 whole-file-conversion class).
  # CR bytes are generated via printf escapes so this self-test's own source
  # stays LF-clean. ----
  D=$(_scenario_dir le-red)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\r\nexit 0\r\n' > "$D/repo/adapters/claude-code/scripts/crlf-script.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-red" 1 "$RC" "RED line-endings" "$OUT"

  # ---- Check: line-endings WARN fixture — LF-clean scripts but no
  # .gitattributes eol pin ----
  D=$(_scenario_dir le-warn)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-missing-pin-warns" 0 "$RC" "WARN line-endings" "$OUT"

  # ---- Check: line-endings GREEN fixture — LF scripts + the eol=lf pin ----
  D=$(_scenario_dir le-green)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-green" 0 "$RC" "" "$OUT"

  # ---- Check: line-endings git-branch RED fixture — exercises the
  # PRODUCTION code path (git ls-files enumeration + -ef toplevel guard +
  # process-substitution RED propagation), which the glob-branch scenarios
  # above cannot reach (their fixture repos are plain directories).
  # git-init'd per NL-FINDING-029: hooksPath cleared so global hooks never
  # fire; autocrlf pinned off so the CRLF bytes written are the bytes kept;
  # `git add` (not commit) suffices for ls-files enumeration — no identity
  # config, no hook cost. ----
  D=$(_scenario_dir le-git-red)
  _stamp_claim_honesty_green "$D"
  if command -v git >/dev/null 2>&1 && git -C "$D/repo" init --quiet >/dev/null 2>&1; then
    git -C "$D/repo" config core.hooksPath ""
    git -C "$D/repo" config core.autocrlf false
    printf '#!/bin/bash\r\nexit 0\r\n' > "$D/repo/adapters/claude-code/scripts/crlf-tracked.sh"
    git -C "$D/repo" add -A >/dev/null 2>&1
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "line-endings-git-red" 1 "$RC" "CR bytes in the working tree" "$OUT"
  else
    echo "self-test (line-endings-git-red): SKIP — git unavailable" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Check: line-endings LIVE-MIRROR WARN fixture (LIVE-MIRROR-CRLF-01)
  # — repo tree is fully clean (LF scripts + eol=lf pin, i.e. what would
  # otherwise be the all-GREEN scenario) but the LIVE mirror's hooks/
  # directory carries CRLF, simulating a mirror built before the
  # .gitattributes pin landed. Must WARN, never RED — this is stale-mirror
  # drift self-healed by re-running install.sh, not an active break. ----
  D=$(_scenario_dir le-live-warn)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  printf '#!/bin/bash\r\nexit 0\r\n' > "$D/live/hooks/crlf-live-hook.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-live-mirror-warns" 0 "$RC" "WARN line-endings.*live mirror carries pre-pin CRLF" "$OUT"

  # ---- Check: line-endings LIVE-MIRROR WARN fixture, hooks/lib/ variant —
  # same as above but the CRLF lives under hooks/lib/ instead of hooks/
  # directly, exercising the second scanned glob. ----
  D=$(_scenario_dir le-live-warn-lib)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  mkdir -p "$D/live/hooks/lib"
  printf '#!/bin/bash\r\nexit 0\r\n' > "$D/live/hooks/lib/crlf-live-lib.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-live-mirror-lib-warns" 0 "$RC" "WARN line-endings.*live mirror carries pre-pin CRLF" "$OUT"

  # ---- Check: line-endings LIVE-MIRROR GREEN fixture — repo clean AND live
  # mirror LF-clean (post-install.sh-normalization steady state). No WARN,
  # no RED. ----
  D=$(_scenario_dir le-live-green)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  printf '#!/bin/bash\nexit 0\n' > "$D/live/hooks/lf-live-hook.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-live-mirror-green" 0 "$RC" "" "$OUT"

  # ---- Check: line-endings LIVE-MIRROR CRLF must never RED, even when
  # combined with an otherwise-red-triggering repo scenario elsewhere in the
  # same run — verifies the live-mirror predicate is additive-WARN-only and
  # cannot itself flip RC to 1. Reuses the le-red repo-CRLF fixture's repo
  # side (which legitimately RC=1s on its own) is NOT what this asserts;
  # instead this scenario keeps the repo clean and only pollutes live, then
  # asserts RC=0 (no RED) while still asserting the WARN text fired. ----
  D=$(_scenario_dir le-live-warn-not-red)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  printf '#!/bin/bash\r\nexit 0\r\n' > "$D/live/scripts/crlf-live-script.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-live-mirror-never-red" 0 "$RC" "WARN line-endings" "$OUT"
  if printf '%s' "$OUT" | grep -q "RED line-endings"; then
    echo "self-test (line-endings-live-mirror-never-red-strict): FAIL (unexpected RED line-endings in output)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (line-endings-live-mirror-never-red-strict): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ============================================================
  # NL Observability Program Wave O, task O.6 (specs-o §O.6) — RED/GREEN
  # self-test scenarios for the six pipeline-health predicates. Spliced
  # from tests/fixtures/wave-o/O.6/doctor-predicate.md (orchestrator
  # integration, batch 2).
  # ============================================================

  # ---- obs-writers-firing: RED — stamp claims MORE lines / LATER mtime
  # than the real file currently has (not-grown-since-last-check) ----
  D=$(_scenario_dir o6-writers-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/doctor-cache"
  printf '{"gate":"x","event":"block","ts":"2026-01-01T00:00:00Z"}\n' > "$D/live/state/signal-ledger.jsonl"
  touch "$D/live/state/signal-ledger.jsonl"
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)
  printf '%s %s\n' "$((now_epoch + 100))" "999" > "$D/live/state/doctor-cache/obs-ledger-stamp.txt"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "o6-obs-writers-firing-red" 1 "$RC" "RED obs-writers-firing" "$OUT"

  # ---- obs-writers-firing: GREEN — no pre-existing stamp (first-run
  # seeds the baseline, does not fail) ----
  D=$(_scenario_dir o6-writers-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state"
  printf '{"gate":"x","event":"block","ts":"2026-01-01T00:00:00Z"}\n' > "$D/live/state/signal-ledger.jsonl"
  touch "$D/live/state/signal-ledger.jsonl"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-writers-firing"; then
    echo "self-test (o6-obs-writers-firing-green): FAIL (unexpected RED)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-writers-firing-green): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-heartbeats-fresh: RED — a fresh transcript with a missing
  # heartbeat file, per-sid naming branch (heartbeats dir EXISTS but the
  # specific sid's file does not — distinct from the "no heartbeats dir
  # at all" branch, which has its own message and is covered by a
  # separate assertion below) ----
  D=$(_scenario_dir o6-hb-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts/proj" "$D/live/state/heartbeats"
  printf '{}\n' > "$D/transcripts/proj/sess-live.jsonl"
  touch "$D/transcripts/proj/sess-live.jsonl"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  _assert "o6-obs-heartbeats-fresh-red" 1 "$RC" "RED obs-heartbeats-fresh" "$OUT"
  if ! printf '%s' "$OUT" | grep -q "sess-live:missing"; then
    echo "self-test (o6-obs-heartbeats-fresh-red-names-sid): FAIL (did not name sess-live:missing)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-red-names-sid): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-heartbeats-fresh: GREEN — a fresh transcript WITH a fresh
  # heartbeat file, plus the zero-live-sessions GREEN case ----
  D=$(_scenario_dir o6-hb-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts/proj" "$D/live/state/heartbeats"
  printf '{}\n' > "$D/transcripts/proj/sess-live.jsonl"
  touch "$D/transcripts/proj/sess-live.jsonl"
  printf '{"schema":1,"session_id":"sess-live"}\n' > "$D/live/state/heartbeats/sess-live.json"
  touch "$D/live/state/heartbeats/sess-live.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-heartbeats-fresh"; then
    echo "self-test (o6-obs-heartbeats-fresh-green): FAIL (unexpected RED)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-green): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  D=$(_scenario_dir o6-hb-green-idle)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-heartbeats-fresh"; then
    echo "self-test (o6-obs-heartbeats-fresh-green-idle): FAIL (unexpected RED on zero live sessions)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-green-idle): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-heartbeats-fresh: GREEN (RED-fixture-adjacent) — a fresh
  # SUBAGENT transcript (under <sid>/subagents/) and a fresh WORKFLOW
  # sub-transcript (under <sid>/workflows/), neither with any heartbeat
  # file anywhere, must stay GREEN. Subagent/workflow transcripts are not
  # independent sessions and never get their own heartbeat writer; before
  # this fix, this exact fixture false-REDed (verifier-round FAIL, O.6
  # conf 9) ----
  D=$(_scenario_dir o6-hb-green-subagent)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts/proj/parent-sid/subagents" "$D/transcripts/proj/parent-sid/workflows"
  printf '{}\n' > "$D/transcripts/proj/parent-sid/subagents/sub-sid.jsonl"
  touch "$D/transcripts/proj/parent-sid/subagents/sub-sid.jsonl"
  printf '{}\n' > "$D/transcripts/proj/parent-sid/workflows/wf-sid.jsonl"
  touch "$D/transcripts/proj/parent-sid/workflows/wf-sid.jsonl"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-heartbeats-fresh"; then
    echo "self-test (o6-obs-heartbeats-fresh-green-subagent): FAIL (unexpected RED on subagent/workflow-only transcripts with no heartbeats)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-green-subagent): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-heartbeats-fresh: GREEN — CANONICAL-ORACLE FIX (O.6
  # re-verifier round, FAIL conf 9, duplicated-staleness-oracle / mid-turn
  # false-stall). A FRESH transcript (touched to now) whose matching
  # heartbeat file has a last_activity_ts 45 minutes old (stale by raw
  # mtime/JSON-timestamp math alone — simulates a long tool-heavy turn
  # with no Stop-time touch yet) and a pid that is genuinely alive (this
  # self-test process's own $$). Before this fix, the predicate computed
  # heartbeat staleness from the heartbeat file's own mtime/age alone and
  # would have false-REDed this exact shape ("sess-midturn:45min"). After
  # the fix (sourcing hooks/lib/session-heartbeat-lib.sh and calling
  # hb_classify, which joins against transcript mtime per contract C1),
  # this must classify `live` (not `missing`) and stay GREEN — proving a
  # long-running turn no longer false-stalls its own session. ----
  D=$(_scenario_dir o6-hb-green-midturn)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts/proj" "$D/live/state/heartbeats"
  printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' > "$D/transcripts/proj/sess-midturn.jsonl"
  touch "$D/transcripts/proj/sess-midturn.jsonl"
  OLD_TS="$(date -u -d '45 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-45M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '2020-01-01T00:00:00Z')"
  cat > "$D/live/state/heartbeats/sess-midturn.json" <<EOF
{"schema":1,"session_id":"sess-midturn","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"${OLD_TS}","last_event":"turn-end","marker_state":"none"}
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-heartbeats-fresh"; then
    echo "self-test (o6-obs-heartbeats-fresh-green-midturn): FAIL (unexpected RED — a fresh transcript with a stale-by-mtime-but-present heartbeat must classify live via the canonical oracle's transcript join, not false-stall)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-green-midturn): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-scheduled-tasks: RED — SCHTASKS_CMD stub reports a bad Last
  # Result code.
  #
  # ORCHESTRATOR FIX: the fragment's own RED/GREEN fixture instructions
  # described SCHTASKS_CMD as a path to an executable stub printing
  # "name<TAB>code" lines. That does not match the REAL script
  # (scripts/scheduled-task-health.sh): SCHTASKS_CMD is `eval`'d as a full
  # shell COMMAND STRING (see _sth_query_output), and its expected output
  # is the RAW `schtasks /Query /V /FO LIST` block format (`TaskName:` /
  # `Last Result:` label lines, task name prefixed with a literal `\`),
  # which _sth_parse_and_filter then reduces to the tab-separated
  # name/code pairs. The original fixtures silently produced zero output
  # (found running this predicate's own scenarios) rather than failing
  # loudly — corrected to the real interface, matching the script's own
  # --self-test fixture shape exactly. ----
  D=$(_scenario_dir o6-sched-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/scripts"
  cp "$SCRIPT_DIR/../scripts/scheduled-task-health.sh" "$D/repo/adapters/claude-code/scripts/scheduled-task-health.sh" 2>/dev/null
  if [[ -f "$D/repo/adapters/claude-code/scripts/scheduled-task-health.sh" ]]; then
    SCHED_FIXTURE_RED=$(cat <<'EOF'
Folder: \
TaskName:                             \NL-fixture-task
Last Result:                          -2147024894
EOF
)
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(SCHTASKS_CMD="printf '%s\n' '${SCHED_FIXTURE_RED}'" _run_quick "$D")"; RC=$?
    _assert "o6-obs-scheduled-tasks-red" 1 "$RC" "RED obs-scheduled-tasks" "$OUT"
    if ! printf '%s' "$OUT" | grep -q "NL-fixture-task"; then
      echo "self-test (o6-obs-scheduled-tasks-red-names-task): FAIL (did not name NL-fixture-task)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-scheduled-tasks-red-names-task): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-obs-scheduled-tasks-red): SKIP (scheduled-task-health.sh not present next to this doctor)" >&2
  fi

  # ---- obs-scheduled-tasks: GREEN — Last Result=0, plus the
  # absent-script WARN-not-RED case ----
  D=$(_scenario_dir o6-sched-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/scripts"
  cp "$SCRIPT_DIR/../scripts/scheduled-task-health.sh" "$D/repo/adapters/claude-code/scripts/scheduled-task-health.sh" 2>/dev/null
  if [[ -f "$D/repo/adapters/claude-code/scripts/scheduled-task-health.sh" ]]; then
    SCHED_FIXTURE_GREEN=$(cat <<'EOF'
Folder: \
TaskName:                             \NL-fixture-task
Last Result:                          0
EOF
)
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(SCHTASKS_CMD="printf '%s\n' '${SCHED_FIXTURE_GREEN}'" _run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "RED obs-scheduled-tasks"; then
      echo "self-test (o6-obs-scheduled-tasks-green): FAIL (unexpected RED)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-scheduled-tasks-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-obs-scheduled-tasks-green): SKIP (scheduled-task-health.sh not present next to this doctor)" >&2
  fi
  D=$(_scenario_dir o6-sched-absent)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-scheduled-tasks"; then
    echo "self-test (o6-obs-scheduled-tasks-absent-script-green): FAIL (unexpected RED when script absent)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-scheduled-tasks-absent-script-green): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-consumer-map: RED — map missing an event type + an entry
  # with zero consumers ----
  D=$(_scenario_dir o6-map-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/observability-consumer-map.json" <<'EOF'
{"schema":1,"event_types":{"block":{"consumers":["digest:x"]},"empty-one":{"consumers":[]}}}
EOF
  mkdir -p "$D/repo/adapters/claude-code/hooks"
  printf '#!/bin/bash\nledger_emit "my-gate" "warn" "detail"\n' > "$D/repo/adapters/claude-code/hooks/fixture-hook.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "o6-obs-consumer-map-red" 1 "$RC" "RED obs-consumer-map" "$OUT"
    if ! printf '%s' "$OUT" | grep -q "warn"; then
      echo "self-test (o6-obs-consumer-map-red-names-warn): FAIL (did not name the unmapped 'warn' literal)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-consumer-map-red-names-warn): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
    if ! printf '%s' "$OUT" | grep -q "empty-one"; then
      echo "self-test (o6-obs-consumer-map-red-names-zero-consumer-entry): FAIL (did not name empty-one)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-consumer-map-red-names-zero-consumer-entry): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-obs-consumer-map-red): SKIP (jq unavailable)" >&2
  fi

  # ---- obs-consumer-map: GREEN — map covers every literal + every entry
  # has >=1 consumer ----
  D=$(_scenario_dir o6-map-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/observability-consumer-map.json" <<'EOF'
{"schema":1,"event_types":{"block":{"consumers":["digest:x"]},"warn":{"consumers":["digest:x"]}}}
EOF
  mkdir -p "$D/repo/adapters/claude-code/hooks"
  printf '#!/bin/bash\nledger_emit "my-gate" "warn" "detail"\n' > "$D/repo/adapters/claude-code/hooks/fixture-hook.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "RED obs-consumer-map"; then
      echo "self-test (o6-obs-consumer-map-green): FAIL (unexpected RED)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-consumer-map-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-obs-consumer-map-green): SKIP (jq unavailable)" >&2
  fi

  # ---- obs-cockpit-fresh: WARN-analog (this predicate is never RED) —
  # cockpit registered, sessions live, stamp stale ----
  D=$(_scenario_dir o6-cockpit-warn)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/workstreams-ui/server" "$D/live/state/heartbeats" "$D/live/state/workstreams-cache"
  printf 'stub\n' > "$D/repo/workstreams-ui/server/server.js"
  printf '{"schema":1}\n' > "$D/live/state/heartbeats/sess-x.json"
  touch "$D/live/state/heartbeats/sess-x.json"
  : > "$D/live/state/workstreams-cache/derived-cache-stamp.txt"
  touch -d '2 hours ago' "$D/live/state/workstreams-cache/derived-cache-stamp.txt" 2>/dev/null \
    || touch -A -020000 "$D/live/state/workstreams-cache/derived-cache-stamp.txt" 2>/dev/null || true
  mkdir -p "$D/fakebin"
  cat > "$D/fakebin/schtasks" <<'STUBEOF'
#!/bin/bash
for a in "$@"; do
  if [[ "$a" == "NL-workstreams-cockpit" ]]; then exit 0; fi
done
exit 0
STUBEOF
  chmod +x "$D/fakebin/schtasks"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(PATH="$D/fakebin:$PATH" _run_quick "$D")"; RC=$?
  # Never RED (max severity is WARN) regardless of whether the stamp-age
  # arithmetic landed >60min on this platform's touch fallback.
  if printf '%s' "$OUT" | grep -q "RED obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-never-red): FAIL (obs-cockpit-fresh must never RED)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-never-red): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  _assert "o6-obs-cockpit-fresh-warn-rc" 0 "$RC" "" "$OUT"

  # ---- obs-cockpit-fresh: GREEN — the common case (workstreams-ui not
  # installed at all) ----
  D=$(_scenario_dir o6-cockpit-green)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -qE "(RED|WARN) obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-green-absent): FAIL (unexpected RED/WARN when workstreams-ui/server absent)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-green-absent): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- needs-you-headers: RED — open decision item + NEEDS-YOU.md
  # missing 2 of 4 canonical headers ----
  D=$(_scenario_dir o6-ny-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/needs-you"
  cat > "$D/live/state/needs-you/ledger.json" <<'EOF'
{"schema_version":1,"items":[{"id":"NY-1","section":"decision","state":"open"}]}
EOF
  cat > "$D/repo/NEEDS-YOU.md" <<'EOF'
## Awaiting your decision
stuff

## In flight (sessions + waves)
stuff
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "o6-needs-you-headers-red" 1 "$RC" "RED needs-you-headers" "$OUT"
    if ! printf '%s' "$OUT" | grep -q "Open questions"; then
      echo "self-test (o6-needs-you-headers-red-names-missing): FAIL (did not name a missing header)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-needs-you-headers-red-names-missing): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-needs-you-headers-red): SKIP (jq unavailable)" >&2
  fi

  # ---- needs-you-headers: GREEN — all 4 headers present; plus the
  # gate-not-triggered GREEN (ny_open==0, headers all missing, still
  # GREEN) ----
  D=$(_scenario_dir o6-ny-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/needs-you"
  cat > "$D/live/state/needs-you/ledger.json" <<'EOF'
{"schema_version":1,"items":[{"id":"NY-1","section":"decision","state":"open"}]}
EOF
  cat > "$D/repo/NEEDS-YOU.md" <<'EOF'
## Awaiting your decision
## Open questions
## In flight (sessions + waves)
## Recently decided for your §8 review
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "RED needs-you-headers"; then
      echo "self-test (o6-needs-you-headers-green): FAIL (unexpected RED)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-needs-you-headers-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-needs-you-headers-green): SKIP (jq unavailable)" >&2
  fi
  D=$(_scenario_dir o6-ny-green-not-triggered)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/needs-you"
  cat > "$D/live/state/needs-you/ledger.json" <<'EOF'
{"schema_version":1,"items":[]}
EOF
  cat > "$D/repo/NEEDS-YOU.md" <<'EOF'
(no headers at all)
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "RED needs-you-headers"; then
      echo "self-test (o6-needs-you-headers-green-gate-not-triggered): FAIL (predicate fired despite ny_open==0)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-needs-you-headers-green-gate-not-triggered): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-needs-you-headers-green-gate-not-triggered): SKIP (jq unavailable)" >&2
  fi

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
