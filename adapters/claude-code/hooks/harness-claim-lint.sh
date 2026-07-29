#!/bin/bash
# harness-claim-lint.sh — catch the three defect CLASSES that recurred inside a
# single session (2026-07-28/29), cheaply, before a reviewer is spent on them.
#
# ============================================================================
# WHY THIS EXISTS
# ============================================================================
# Over roughly 24 hours, adversarial review (harness-reviewer + task-verifier)
# caught every one of the following. The builder caught none of them. Review is
# the mechanism that works — but a reviewer is expensive and slow, and these
# three classes are mechanically detectable, so spending a reviewer to re-find
# them each time is waste.
#
# CLASS 1 — SELF-INVALIDATING SANDBOX TEST. A --self-test asserts that a
#   production path does NOT EXIST, conflating "the artifact exists" with "my
#   test created it." The suite then goes RED precisely because the feature
#   started working. Occurred THREE times:
#     • admission-lib.sh Scenario 16 asserted ~/.claude/state/governor absent;
#       once production traffic created it the suite read 37/1, and the "38/0"
#       in the commit message was only reproducible on a machine where the
#       deliverable did not work.
#     • the T3 integration script repeated it verbatim.
#     • model-availability.sh Scenario 7 repeated it a third time.
#   The correct form is a BEFORE/AFTER DELTA on the real artifact.
#
# CLASS 2 — ABSOLUTE OR PERFORMANCE CLAIM WITH NO MEASUREMENT. Prose asserting
#   "spawn-free", "~0 ms", "forks at most once", "nothing can", "never" — with
#   no cited command or number. Occurred at least four times:
#     • "SPAWN-FREE HOT PATH ... forks at most ONCE ... ~0 ms" measured 70.8 ms
#       across ~45 forks.
#     • "Nothing here trusts a caller-supplied claim" — four environment
#       channels did, one of which bypassed the HALT kill switch.
#     • doctrine "runtime applies the fallback if the primary is unavailable" —
#       no code anywhere implemented it.
#     • "the defense lives HERE rather than per-caller" — inert for 1 of 3 hosts.
#   Constitution §1: never claim behavior without a mechanism that triggers it.
#
# CLASS 3 — GUARD ITS CALLERS DO NOT ARM. A lib gates behavior on an env var
#   (HARNESS_SELFTEST, a *_DIR override) and a host that calls it never sets it,
#   so the protection is silently inert for that host. Occurred once, costing
#   real data: spawn-worktree.sh --self-test wrote fabricated rows into the
#   operator's live would-block ledger for four review rounds.
#
# ============================================================================
# POSTURE
# ============================================================================
# WARN-ONLY (always exit 0). These are heuristics over prose and shell, and a
# false positive that BLOCKS a commit trains the operator to route around the
# harness — the cardinal gate failure this repo has already paid for. It prints
# what it found and why; a human or reviewer decides. Constitution §10: no
# blocking gate without a measured false-positive rate, and this has none yet.
# Promotion condition: a measured FP rate over a real observation window, the
# same bar review-record-commit-gate.sh met retroactively.
#
# Usage:  harness-claim-lint.sh [--staged | <file>...]
#         harness-claim-lint.sh --self-test
# ============================================================================

set -uo pipefail
_HCL_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_HCL_FINDINGS=0

_hcl_report() { # <class> <file> <line> <detail>
  _HCL_FINDINGS=$((_HCL_FINDINGS+1))
  printf '  [%s] %s:%s\n      %s\n' "$1" "$2" "$3" "$4" >&2
}

# --- CLASS 1: self-test asserting a production path is ABSENT ---------------
_hcl_check_sandbox_absence() {
  local f="$1"
  # Read into an array so the failure branch can be found on a LATER line — the
  # real occurrences all split the existence test and its fail() across lines,
  # which a same-line-only check misses (this lint's own first draft did).
  local -a L=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do L+=("$line"); done < "$f"
  local i j n=${#L[@]}
  for (( i=0; i<n; i++ )); do
    case "${L[$i]}" in
      *'-e "$HOME/.claude'*|*'-d "$HOME/.claude'*|*'-e "$real'*|*'-d "$real'*|\
      *'-e "$REAL'*|*'-d "$REAL'*|*'-e "$_real'*|*'-d "$_real'*) ;;
      *) continue ;;
    esac
    # look ahead a few lines for a failure assertion tied to this existence test
    for (( j=i; j<i+4 && j<n; j++ )); do
      case "${L[$j]}" in
        *fail\ *|*fail_\ *|*'FAIL'*)
          # a DELTA-style check mentions before/after and is the correct form
          case "${L[$j]}" in *before*|*delta*|*DELTA*|*unchanged*) continue ;; esac
          _hcl_report "CLASS1 self-invalidating-sandbox-test" "$f" "$((i+1))" \
            "asserts a production path is ABSENT; it goes RED once the feature legitimately creates it. Use a before/after DELTA on the real artifact instead."
          break ;;
      esac
    done
  done
}

# --- CLASS 2: absolute / perf claim with no measurement nearby --------------
_hcl_check_unmeasured_claim() {
  local f="$1" n=0 line low
  while IFS= read -r line; do
    n=$((n+1))
    case "$line" in \#*|*'#'*) ;; *) continue ;; esac   # comments/prose only
    low="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    case "$low" in
      *spawn-free*|*"no forks"*|*"zero overhead"*|*"~0 ms"*|*"0ms"*|*"forks at most"*|\
      *"nothing can"*|*"never possible"*|*"cannot happen"*|*"impossible by"*|*"always falls back"*)
        # a nearby measurement or citation redeems it
        case "$low" in
          *measured*|*"ms/dispatch"*|*"file:line"*|*proven*|*"self-test"*|*retired*|*refuted*|*hypothesized*) ;;
          *)
            _hcl_report "CLASS2 unmeasured-claim" "$f" "$n" \
              "absolute/performance claim with no measurement, command, or PROVEN/HYPOTHESIZED label (constitution §1). Cite the number or restate as hypothesized." ;;
        esac ;;
    esac
  done < "$f"
}

# --- CLASS 3: a guard whose callers do not arm it ---------------------------
# If a lib keys behavior on HARNESS_SELFTEST, every script that CALLS that lib's
# entry points must set it in its own --self-test branch.
_hcl_check_unarmed_guard() {
  local root="$1"
  local lib_fns="adm_admit"     # extend as new guarded libs land
  local fn f
  for fn in $lib_fns; do
    for f in "$root"/hooks/*.sh "$root"/scripts/*.sh; do
      [[ -f "$f" ]] || continue
      grep -q "$fn" "$f" 2>/dev/null || continue
      grep -q -- '--self-test' "$f" 2>/dev/null || continue
      if ! grep -q 'HARNESS_SELFTEST' "$f" 2>/dev/null; then
        _hcl_report "CLASS3 unarmed-guard" "$f" "-" \
          "calls $fn and has a --self-test, but never sets HARNESS_SELFTEST — the lib's sandbox guard is INERT for this host, so its self-test writes to REAL operator state."
      fi
    done
  done
}

_hcl_main() {
  local -a files=()
  if [[ "${1:-}" == "--staged" ]]; then
    local root; root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
    while IFS= read -r p; do
      [[ -n "$p" ]] && [[ -f "$root/$p" ]] && files+=("$root/$p")
    done < <(git -C "$root" diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep '\.sh$')
  else
    files=("$@")
  fi

  local f
  for f in "${files[@]:-}"; do
    [[ -f "$f" ]] || continue
    _hcl_check_sandbox_absence "$f"
    _hcl_check_unmeasured_claim "$f"
  done

  local hroot="$_HCL_SELF_DIR/.."
  [[ -d "$hroot/hooks" ]] && _hcl_check_unarmed_guard "$hroot"

  if [[ "$_HCL_FINDINGS" -gt 0 ]]; then
    {
      echo ""
      echo "harness-claim-lint: $_HCL_FINDINGS finding(s) — WARN ONLY, nothing blocked."
      echo "These are the three classes that recurred within one session on 2026-07-28/29;"
      echo "each was caught by an adversarial reviewer, not by the builder. Fixing them here"
      echo "is cheaper than spending a reviewer to re-find them."
    } >&2
  fi
  return 0    # ALWAYS 0 — warn-only by design
}

_hcl_self_test() {
  local P=0 F=0
  pass() { P=$((P+1)); echo "  PASS: $*"; }
  fail() { F=$((F+1)); echo "  FAIL: $*"; }
  local T; T="$(mktemp -d)"

  cat > "$T/bad1.sh" <<'EOF'
#!/bin/bash
_t() {
  if [[ -e "$HOME/.claude/state/governor" ]]; then
    fail "real governor state dir exists"
  fi
}
EOF
  local out; out="$(_HCL_FINDINGS=0; _hcl_check_sandbox_absence "$T/bad1.sh" 2>&1)"
  case "$out" in *CLASS1*) pass "CLASS1 detected: self-test asserting a production path is absent" ;;
    *) fail "CLASS1 missed" ;; esac

  cat > "$T/bad2.sh" <<'EOF'
#!/bin/bash
# SPAWN-FREE HOT PATH: uses builtins only, ~0 ms per call.
EOF
  out="$(_HCL_FINDINGS=0; _hcl_check_unmeasured_claim "$T/bad2.sh" 2>&1)"
  case "$out" in *CLASS2*) pass "CLASS2 detected: spawn-free / ~0 ms with no measurement" ;;
    *) fail "CLASS2 missed" ;; esac

  cat > "$T/good2.sh" <<'EOF'
#!/bin/bash
# Hot path MEASURED at 70.8 ms/dispatch with a snapshot present; the earlier
# spawn-free claim was refuted and retired.
EOF
  out="$(_HCL_FINDINGS=0; _hcl_check_unmeasured_claim "$T/good2.sh" 2>&1)"
  case "$out" in *CLASS2*) fail "CLASS2 false positive on a measured, retired claim" ;;
    *) pass "CLASS2 stays silent when a measurement is cited (FP control)" ;; esac

  # CLASS 3 against the REAL tree — spawn-worktree.sh was the real offender and
  # is now fixed, so this must be silent.
  out="$(_HCL_FINDINGS=0; _hcl_check_unarmed_guard "$_HCL_SELF_DIR/.." 2>&1)"
  case "$out" in *CLASS3*) fail "CLASS3 fires on the real tree — a host still does not arm the guard: $out" ;;
    *) pass "CLASS3 silent on the real tree (all adm_admit hosts arm HARNESS_SELFTEST)" ;; esac

  # warn-only invariant
  _hcl_main "$T/bad1.sh" >/dev/null 2>&1; local rc=$?
  [[ "$rc" == "0" ]] && pass "WARN-ONLY invariant: findings still exit 0" || fail "lint blocked (rc=$rc) — it must never block"

  rm -rf "$T"
  echo
  echo "self-test summary: $P passed, $F failed"
  [[ "$F" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) _hcl_self_test; exit $? ;;
    *) _hcl_main "$@"; exit 0 ;;
  esac
fi
