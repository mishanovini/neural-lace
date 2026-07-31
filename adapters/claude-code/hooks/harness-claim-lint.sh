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
#   This check is BEHAVIORAL (it runs each host and looks at what it wrote) and
#   DISCOVERED (it finds the guarded libs and their hosts from the tree). Its
#   first version was neither, and had the very defect it exists to catch — see
#   the long note above _hcl_check_unarmed_guard.
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
# Usage:  harness-claim-lint.sh [--staged | <file>...]   scoped: CLASS3 probes
#                                                        only hosts in scope
#         harness-claim-lint.sh --all-hosts              full CLASS3 sweep of
#                                                        every discovered host
#                                                        (an AUDIT: ~110s here)
#         harness-claim-lint.sh --self-test
#
# With no arguments at all, CLASS3 sweeps every discovered host (--all-hosts).
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

# --- CLASS 3: a guard whose HOSTS do not arm it -----------------------------
# ============================================================================
# BEHAVIORAL, NOT TEXTUAL — AND DISCOVERED, NOT HARDCODED.
# ============================================================================
# v1 of this check had the exact defect it exists to catch. It decided whether
# a host armed the guard with:   grep -q 'HARNESS_SELFTEST' "$f"
# grep matches COMMENTS. task-verifier falsified it on 2026-07-29 by deleting
# every real `export HARNESS_SELFTEST=1` from all three hosts while leaving the
# explanatory comments intact — the check still reported PASS. Text presence is
# not behavior: "the variable is mentioned" is not "the guard is armed", and a
# `grep` for a name cannot tell a live export from a paragraph about one.
#
# The oracle is now the one admission-lib.sh Scenario 16b uses (read it as the
# reference): run the host's OWN --self-test in a THROWAWAY HOME with the guard
# vars UNSET, then look at what materialised under that HOME's .claude/. The
# sandbox HOME starts empty, so anything found there is state the host would
# have written into the operator's REAL ~/.claude for real. That fails if and
# only if the host actually pollutes — which no comment can fake.
#
# v1 was also HARDCODED (`lib_fns="adm_admit"` plus a fixed hooks/scripts glob),
# so a newly-spliced host was silently unchecked and only ONE of the tree's
# guarded libs was covered at all. Discovery now derives both the guarded libs
# and their hosts from the tree itself. Measured on this tree 2026-07-29, that
# widened coverage from 3 hosts of 1 lib to 33 hosts of 7 libs and surfaced 15
# real instances — 13 of them writing the operator's REAL
# $HOME/.claude/state/signal-ledger.jsonl from a --self-test (same guard shape,
# same defect, 13x the scale of the incident that prompted this file).
#
# SCOPE. With a file scope (--staged / explicit paths) only hosts inside that
# scope are probed. That is what keeps the check cheap AND keeps the promise:
# splicing a lib into a host means EDITING that host, so a new splice is always
# in scope and can never be silently unchecked. `--all-hosts` (or no args at
# all) sweeps every discovered host — that is an audit, and it costs ~110s here.

# Strip shell comments. EVERY discovery and decision below reads STRIPPED text,
# so no comment can satisfy any of them. This is the single line whose absence
# caused the v1 defect.
# NOTE: callers capture this into a variable and then match with `case` or a
# HERE-STRING — never `_hcl_strip f | grep -q ...`. Under `set -o pipefail`,
# grep -q exits at the first match, sed takes SIGPIPE (141), and pipefail makes
# the whole pipeline "fail", so the match is silently discarded. That bug made
# discovery see 2 of 7 guarded libs on the first run of this rewrite.
_hcl_strip() { sed -e 's/[[:space:]]*#.*$//' "$1" 2>/dev/null; }

# DISCOVERY 1 — guarded libs. A lib qualifies when it gates on
# ${HARNESS_SELFTEST...} in CODE *and* names a .claude/ production path, i.e.
# the guard exists precisely to keep self-tests off real operator state.
#
# The path test deliberately matches only `.claude/` and NOT `$HOME/.claude/`.
# Libs write that path several ways — `"$HOME/.claude/state/governor"` but also
# `"${HOME:-$PWD}/.claude/state/perf"` and `printf '%s/.claude/state/...' "$HOME"`
# — and an over-tight pattern silently dropped perf-ledger.sh and
# progress-log-lib.sh (8 hosts) on the first run of this rewrite. The two error
# directions are NOT symmetric: over-including a lib costs one sandboxed probe
# that finds nothing, while under-including one recreates exactly the silent
# hole this rewrite exists to close. So this biases toward including.
_hcl_guarded_libs() {
  local root="$1" L txt
  for L in "$root"/hooks/lib/*.sh; do
    [[ -f "$L" ]] || continue
    txt="$(_hcl_strip "$L")"
    case "$txt" in *'${HARNESS_SELFTEST'*) ;; *) continue ;; esac
    case "$txt" in *'.claude/'*) ;; *) continue ;; esac
    printf '%s\n' "$L"
  done
}

# DISCOVERY 2 — the override vars the guarded libs honour (ADM_STATE_DIR,
# SIGNAL_LEDGER_PATH, HARNESS_SELFTEST_DIR, ...). The sandbox unsets them so an
# ambient value inherited from the operator's shell (or from an enclosing
# self-test) cannot mask a host's failure to arm the guard.
_hcl_guard_vars() {
  local root="$1" L
  printf '%s\n' 'HARNESS_SELFTEST' 'HARNESS_SELFTEST_DIR'
  while IFS= read -r L; do
    [[ -n "$L" ]] || continue
    grep -oE '\$\{[A-Z][A-Z0-9_]*(_DIR|_PATH)' <<< "$(_hcl_strip "$L")" | sed -e 's/^\${//'
  done <<< "$(_hcl_guarded_libs "$root")"
  return 0
}

# DISCOVERY 3 — hosts of a lib: a REAL `source`/`.` line (not a comment, not a
# passing mention in prose) plus a --self-test branch of the host's own.
_hcl_lib_hosts() {
  local root="$1" L="$2" base self H txt
  base="$(basename "$L")"
  self="$(basename "${BASH_SOURCE[0]}")"
  for H in "$root"/hooks/*.sh "$root"/hooks/lib/*.sh "$root"/scripts/*.sh; do
    [[ -f "$H" ]] || continue
    [[ "$H" == "$L" ]] && continue
    [[ "$(basename "$H")" == "$self" ]] && continue
    txt="$(_hcl_strip "$H")"
    case "$txt" in *--self-test*) ;; *) continue ;; esac
    grep -qE "^[[:space:]]*(source|\.)[[:space:]]+.*$base" <<< "$txt" || continue
    printf '%s\n' "$H"
  done
}

# Portable per-host time cap. A lint that can hang a commit is worse than the
# defect it catches. No `timeout` (absent on stock macOS), no `date -d`.
_hcl_run_capped() { # <seconds> <cmd...>
  local secs="$1"; shift
  "$@" &
  local pid=$! ticks=0 max=$((secs * 5))
  while [ "$ticks" -lt "$max" ]; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2 2>/dev/null || sleep 1
    ticks=$((ticks + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124
  fi
  wait "$pid" 2>/dev/null
  return 0
}

# THE ORACLE — run <host> --self-test in a throwaway HOME with the guard vars
# unset, then print whatever it created under that HOME's .claude/ (empty means
# the host is clean). Nothing here reads the host's text.
_hcl_probe_host() { # <host> <sandbox-home> <cwd> <var>...
  local H="$1" sb="$2" cwd="$3"; shift 3
  local v; local -a ev=()
  for v in "$@"; do ev[${#ev[@]}]="-u"; ev[${#ev[@]}]="$v"; done
  [[ "${#ev[@]}" -gt 0 ]] || return 0
  mkdir -p "$sb" 2>/dev/null
  ( cd "$cwd" 2>/dev/null || cd /
    _hcl_run_capped "${HCL_HOST_TIMEOUT:-45}" \
      env "${ev[@]}" HOME="$sb" bash "$H" --self-test ) >/dev/null 2>&1
  [[ -d "$sb/.claude" ]] || return 0
  ( cd "$sb" 2>/dev/null && find .claude -mindepth 1 2>/dev/null | sort | head -6 | tr '\n' ' ' )
}

_hcl_check_unarmed_guard() { # <root> <scoped:0|1> [scope-file...]
  local root="$1" scoped="$2"; shift 2
  root="$(cd "$root" 2>/dev/null && pwd)" || return 0
  [[ -n "$root" ]] || return 0

  # normalise the scope to absolute paths so discovery paths compare equal
  local scope_list="" s
  for s in "$@"; do
    [[ -f "$s" ]] || continue
    scope_list="$scope_list
$(cd "$(dirname "$s")" 2>/dev/null && pwd)/$(basename "$s")"
  done

  local libs; libs="$(_hcl_guarded_libs "$root")"
  [[ -n "$libs" ]] || return 0
  local vars; vars="$(_hcl_guard_vars "$root" | sort -u | tr '\n' ' ')"

  # host -> which guarded libs it sources (used only for the message)
  local pairs="" L H
  while IFS= read -r L; do
    [[ -n "$L" ]] || continue
    while IFS= read -r H; do
      [[ -n "$H" ]] || continue
      pairs="$pairs
$H|$(basename "$L")"
    done <<< "$(_hcl_lib_hosts "$root" "$L")"
  done <<< "$libs"

  local hosts; hosts="$(printf '%s\n' "$pairs" | grep -v '^$' | cut -d'|' -f1 | sort -u)"
  [[ -n "$hosts" ]] || return 0

  # Probe from the lint's OWN repo root: some hosts' self-tests need to run
  # inside a git work tree, and the scanned root may be a mirror in /tmp.
  local cwd="${HCL_PROBE_CWD:-}"
  [[ -n "$cwd" ]] || cwd="$(git -C "$_HCL_SELF_DIR" rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$cwd" ]] || cwd="$root"

  local T; T="$(mktemp -d)" || return 0
  local made whichlibs
  while IFS= read -r H; do
    [[ -n "$H" ]] || continue
    if [[ "$scoped" == "1" ]]; then
      grep -qxF "$H" <<< "$scope_list" || continue
    fi
    made="$(_hcl_probe_host "$H" "$T/$(printf '%s' "$H" | tr '/' '_')" "$cwd" $vars)"
    [[ -n "$made" ]] || continue
    whichlibs="$(grep -F "$H|" <<< "$pairs" | cut -d'|' -f2 | sort -u | tr '\n' ' ')"
    _hcl_report "CLASS3 unarmed-guard" "$H" "-" \
      "its --self-test WROTE REAL OPERATOR STATE into a clean HOME: $made(host sources guarded lib(s): $whichlibs). The lib's sandbox guard is INERT for this host because the host never arms it. Fix: export HARNESS_SELFTEST=1 in this script's own --self-test branch."
  done <<< "$hosts"
  rm -rf "$T"
  return 0
}

_hcl_main() {
  local -a files=()
  local scoped=1
  if [[ "${1:-}" == "--staged" ]]; then
    local root; root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
    while IFS= read -r p; do
      [[ -n "$p" ]] && [[ -f "$root/$p" ]] && files+=("$root/$p")
    done < <(git -C "$root" diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep '\.sh$')
  elif [[ "${1:-}" == "--all-hosts" ]]; then
    scoped=0                       # full CLASS3 audit sweep
  elif [[ "$#" -eq 0 ]]; then
    scoped=0                       # no argument at all == whole-tree audit
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
  if [[ -d "$hroot/hooks" ]]; then
    if [[ "$scoped" == "1" ]]; then
      _hcl_check_unarmed_guard "$hroot" 1 ${files[@]+"${files[@]}"}
    else
      _hcl_check_unarmed_guard "$hroot" 0
    fi
  fi

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

  # ---- CLASS 3 -------------------------------------------------------------
  # NOTE ON METHOD: no hand-written host fixture is used anywhere below. The
  # artifact of the proven 2026-07-29 defect (scripts/spawn-worktree.sh) exists,
  # so IT is the oracle; the mutation runs against a byte-for-byte MIRROR of the
  # real tree so the repo is never touched. A fixture would only prove that the
  # matcher matches the fixture.
  local RT; RT="$(cd "$_HCL_SELF_DIR/.." 2>/dev/null && pwd)"

  # (a) DISCOVERY is real — no hardcoded list. v1 covered exactly one lib
  #     (`lib_fns="adm_admit"`); this must find several.
  local dlibs; dlibs="$(_hcl_guarded_libs "$RT")"
  local nlibs; nlibs="$(printf '%s\n' "$dlibs" | grep -c . | tr -d ' ')"
  if [[ "$nlibs" -ge 2 ]]; then
    pass "CLASS3 discovery finds $nlibs guarded libs (v1 hardcoded exactly 1)"
  else
    fail "CLASS3 discovery found only $nlibs guarded lib(s) — discovery is not working"
  fi

  # REGRESSION GUARD: these two resolve production state as ${HOME:-$PWD}/.claude
  # rather than $HOME/.claude, and an over-tight path pattern dropped both (8
  # hosts) during this rewrite. Silent under-discovery is the failure mode here.
  local missed=""
  case "$dlibs" in *perf-ledger.sh*) ;; *) missed="$missed perf-ledger.sh" ;; esac
  case "$dlibs" in *progress-log-lib.sh*) ;; *) missed="$missed progress-log-lib.sh" ;; esac
  [[ -z "$missed" ]] \
    && pass "CLASS3 discovery covers \${HOME:-\$PWD}-style libs too (perf-ledger, progress-log-lib)" \
    || fail "CLASS3 discovery silently dropped guarded lib(s):$missed — their hosts would go unchecked"

  # (b) DISCOVERY reaches the known host without being told about it.
  local sw_found=no L lhosts
  while IFS= read -r L; do
    [[ -n "$L" ]] || continue
    lhosts="$(_hcl_lib_hosts "$RT" "$L")"     # capture first: see _hcl_strip note
    case "$lhosts" in *scripts/spawn-worktree.sh*) sw_found=yes ;; esac
  done <<< "$(_hcl_guarded_libs "$RT")"
  [[ "$sw_found" == "yes" ]] \
    && pass "CLASS3 discovery reaches scripts/spawn-worktree.sh with no hardcoded host list" \
    || fail "CLASS3 discovery did NOT find scripts/spawn-worktree.sh — a spliced host would go unchecked"

  # (c) THE DISCRIMINATING TEST. Mirror the real tree; revert ONLY the code line
  #     in the real host and KEEP its comment. v1's "RED proof" was fake because
  #     it stashed the whole file, comment included — a red produced by removing
  #     the comment too proves nothing about a comment-blind matcher.
  local MT="$T/mirror"
  mkdir -p "$MT"
  cp -R "$RT/hooks" "$MT/hooks" 2>/dev/null
  cp -R "$RT/scripts" "$MT/scripts" 2>/dev/null
  local MH="$MT/scripts/spawn-worktree.sh"
  if [[ ! -f "$MH" ]]; then
    fail "mirror is missing scripts/spawn-worktree.sh — cannot run the discriminating test"
  else
    # GREEN first: the pristine real host must NOT be flagged.
    out="$(_HCL_FINDINGS=0; _hcl_check_unarmed_guard "$MT" 1 "$MH" 2>&1)"
    case "$out" in
      *CLASS3*) fail "CLASS3 false positive — pristine spawn-worktree.sh flagged: $out" ;;
      *) pass "CLASS3 GREEN on the pristine real host (armed guard leaves the sandbox HOME clean)" ;;
    esac

    # revert ONLY the export; the explanatory comment block stays untouched.
    sed -e 's/; export HARNESS_SELFTEST=1 ;;/; ;;/' "$MH" > "$MH.mut" && mv "$MH.mut" "$MH"
    chmod +x "$MH" 2>/dev/null

    # Verify the mutation is TRUE-RED-shaped BEFORE trusting the red it produces:
    # the code must be gone while the comment still mentions the variable, so a
    # textual grep would still (wrongly) call this host armed.
    if _hcl_strip "$MH" | grep -q 'HARNESS_SELFTEST'; then
      fail "mutation did not remove the CODE (stripped text still has it) — mutation is wrong"
    elif grep -q 'HARNESS_SELFTEST' "$MH"; then
      pass "mutation is TRUE-RED-shaped: code gone, COMMENT intact (a textual grep still reports 'armed')"
    else
      fail "mutation removed the comment too — that red would be a FALSE red, exactly v1's mistake"
    fi

    out="$(_HCL_FINDINGS=0; _hcl_check_unarmed_guard "$MT" 1 "$MH" 2>&1)"
    case "$out" in
      *CLASS3*) pass "CLASS3 RED when only the code is reverted — the behavioral oracle is not fooled by the comment" ;;
      *) fail "CLASS3 MISSED the reverted host — the check is INERT (this is the v1 defect): $out" ;;
    esac
  fi

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
