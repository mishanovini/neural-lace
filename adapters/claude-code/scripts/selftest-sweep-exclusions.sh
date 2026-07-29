#!/usr/bin/env bash
# selftest-sweep-exclusions.sh — reader + validator for the ONE machine-readable
# ledger of scripts a `--self-test` sweep must skip.
#
# Plan: docs/plans/macos-portability-2026-07.md, task M6.
# Ledger: adapters/claude-code/config/selftest-sweep-exclusions.txt
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
# M6 asked for the disposition of the 3 residual attic/ self-test failures and
# said "silence is not" an acceptable outcome. One was fixed
# (attic/workstreams-state-gate.sh, 29/2 -> 31/0 on both interpreters). The
# other two are formally excluded — and an exclusion that lives in a comment is
# exactly the silence M6 forbids, so it lives in a file with a reader (this
# script) and a validator (--check) that harness-doctor.sh runs.
#
# The three anti-rot controls --check enforces, each of which turns a forgotten
# exclusion into a failing gate rather than a silent skip:
#
#   C1  every excluded path EXISTS. The two entries are retirees awaiting the
#       attic README's one-release hard-delete; when that delete lands, this
#       RED is what forces the ledger line to be deleted in the same commit.
#   C2  every entry carries a >=40-character reason. Blocks the "n/a" /
#       "flaky" exclusion that carries no root cause.
#   C3  no excluded path is under hooks/ or scripts/. Those are LIVE control
#       surfaces: a failing live self-test gets FIXED or RETIRED, never
#       silenced. This is the abuse this file would otherwise invite.
#
# and one slower control, --verify (doctor --full / the M5 sweep runner):
#
#   C4  every excluded script's --self-test STILL FAILS. If one starts
#       passing, the exclusion is stale and must be deleted. WARN not RED:
#       nothing is broken when a script gets healthier, but the ledger is
#       lying and must be reconciled.
#
# ============================================================
# CONSUMING THIS FROM A SWEEP RUNNER (the M5 contract)
# ============================================================
# As of this commit the M5 sweep runner does not exist yet (no sweep runner is
# committed under adapters/claude-code/scripts/; verified by grep at authoring
# time). This script therefore DEFINES the format M5 must read rather than
# adopting one. The stable API is one line:
#
#     EXCLUDED="$(bash adapters/claude-code/scripts/selftest-sweep-exclusions.sh --list)"
#
# `--list` prints repo-relative paths, one per line, no comments, no reasons —
# so a runner can skip them with a plain string compare and needs no parser of
# its own. M5's runner should additionally call `--check` (fast, no
# subprocesses) so a rotted ledger fails the sweep, and `--verify` in its
# thorough mode.
#
# ============================================================
# PRIOR ART (deliberately not reused)
# ============================================================
# .github/workflows/hooks-selftest.yml carries KNOWN_FAILING_HOOKS, a bash
# array embedded in GitHub-Actions YAML. It is not reused because it is (a)
# BASENAME-keyed, so it cannot distinguish attic/decision-context-gate.sh from
# the live exit-0 shim hooks/decision-context-gate.sh, (b) unreadable by a
# local runner without a YAML parser, and (c) documented in docs/findings.md
# NL-FINDING-018 as already vestigial for these very entries, since CI globs
# adapters/claude-code/hooks/*.sh and never sweeps attic/ at all. Reconciling
# the CI allowlist onto this ledger is a follow-up, logged in docs/backlog.md.
#
# ============================================================
# PORTABILITY
# ============================================================
# Runs on Apple bash 3.2.57 and Homebrew bash 5.3.15: no `declare -A`, no
# `mapfile`, no `${x^^}`, no `date -d`, no bare `timeout`, no GNU-only
# `sed -i`. Child self-tests run under "$BASH" (the interpreter running THIS
# script), never a bare `bash` — a bare `bash` silently tests whichever
# interpreter is first on PATH, which is how a sweep once reported a result
# for an interpreter it never ran.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# Bounded child execution (M3's primitive). Fail-open to a plain call with a
# loud warning if the lib is absent, matching harness-doctor.sh's own fallback.
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local s="${1:-0}"; shift 2>/dev/null || true
    echo "selftest-sweep-exclusions: WARN hooks/lib/portable-timeout.sh missing — running UNBOUNDED (wanted ${s}s)" >&2
    [ "$#" -gt 0 ] || return 2
    "$@"
  }
fi

MIN_REASON_CHARS=40
LIVE_SURFACES="adapters/claude-code/hooks/ adapters/claude-code/scripts/"

# ------------------------------------------------------------
# resolve_repo_root — mirrors harness-doctor.sh's resolver order.
# ------------------------------------------------------------
resolve_repo_root() {
  if [ -n "${NL_REPO_ROOT:-}" ] && [ -d "${NL_REPO_ROOT}" ]; then
    printf '%s\n' "$NL_REPO_ROOT"; return 0
  fi
  local root
  root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$root" ]; then printf '%s\n' "$root"; return 0; fi
  # scripts/ -> claude-code/ -> adapters/ -> repo root
  root="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)" || return 1
  [ -n "$root" ] && { printf '%s\n' "$root"; return 0; }
  return 1
}

# ------------------------------------------------------------
# ledger_path — the ledger file, repo-side (config/ is not installed
# into ~/.claude; model-policy.json resolves the same way).
# Override with NL_SELFTEST_EXCLUSIONS_FILE (used by --self-test).
# ------------------------------------------------------------
ledger_path() {
  if [ -n "${NL_SELFTEST_EXCLUSIONS_FILE:-}" ]; then
    printf '%s\n' "$NL_SELFTEST_EXCLUSIONS_FILE"; return 0
  fi
  local root
  root="$(resolve_repo_root)" || return 1
  printf '%s\n' "${root}/adapters/claude-code/config/selftest-sweep-exclusions.txt"
}

# ------------------------------------------------------------
# do_list — repo-relative excluded paths, one per line. THE API.
# Exit 0 with empty output when the ledger is absent (an absent ledger
# means "nothing excluded", never "sweep nothing").
# ------------------------------------------------------------
do_list() {
  local f line path rest
  f="$(ledger_path)" || return 0
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    # blank / whitespace-only
    case "$line" in
      *[![:space:]]*) : ;;
      *) continue ;;
    esac
    # comment (leading whitespace tolerated)
    case "$line" in
      [[:space:]]*'#'*) continue ;;
      '#'*) continue ;;
    esac
    # shellcheck disable=SC2034
    read -r path rest <<EOF
$line
EOF
    [ -n "${path:-}" ] || continue
    printf '%s\n' "$path"
  done < "$f"
  return 0
}

# ------------------------------------------------------------
# do_check — C1/C2/C3. Prints RED lines; exit 1 if any RED.
# ------------------------------------------------------------
do_check() {
  local f root line path reason reds=0 entries=0 surface
  f="$(ledger_path)" || {
    echo "[exclusions] WARN repo root unresolvable — ledger not checked"
    return 0
  }
  if [ ! -f "$f" ]; then
    echo "[exclusions] WARN ledger absent at ${f} — nothing excluded"
    return 0
  fi
  root="$(resolve_repo_root)" || root=""

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      *[![:space:]]*) : ;;
      *) continue ;;
    esac
    case "$line" in
      [[:space:]]*'#'*) continue ;;
      '#'*) continue ;;
    esac
    read -r path reason <<EOF
$line
EOF
    [ -n "${path:-}" ] || continue
    entries=$((entries + 1))

    # C1 — the excluded path must exist.
    if [ -n "$root" ] && [ ! -f "${root}/${path}" ]; then
      echo "[exclusions] RED C1 ${path}: excluded path does not exist — delete this ledger line (a hard-delete must remove its exclusion in the same commit)"
      reds=$((reds + 1))
    fi

    # C2 — the reason must state a root cause.
    if [ "${#reason}" -lt "$MIN_REASON_CHARS" ]; then
      echo "[exclusions] RED C2 ${path}: reason is ${#reason} chars, minimum ${MIN_REASON_CHARS} — state the ROOT CAUSE, not that it fails"
      reds=$((reds + 1))
    fi

    # C3 — never silence a live control surface.
    for surface in $LIVE_SURFACES; do
      case "$path" in
        "$surface"*)
          echo "[exclusions] RED C3 ${path}: lives on a LIVE surface (${surface}) — a failing live self-test gets FIXED or RETIRED to attic/, never excluded"
          reds=$((reds + 1))
          ;;
      esac
    done
  done < "$f"

  if [ "$reds" -gt 0 ]; then
    echo "[exclusions] ${reds} RED across ${entries} entries (${f})"
    return 1
  fi
  echo "[exclusions] OK ${entries} entries, 0 red (${f})"
  return 0
}

# ------------------------------------------------------------
# do_verify — C4. Each excluded script's --self-test must STILL FAIL.
# WARN (exit 0) when one now passes: the exclusion is stale.
# ------------------------------------------------------------
do_verify() {
  local root path stale=0 checked=0 rc
  root="$(resolve_repo_root)" || {
    echo "[exclusions] WARN repo root unresolvable — verify skipped"
    return 0
  }
  while IFS= read -r path || [ -n "$path" ]; do
    [ -n "$path" ] || continue
    [ -f "${root}/${path}" ] || continue
    checked=$((checked + 1))
    HARNESS_SELFTEST=1 nl_run_bounded "${NL_EXCLUSIONS_VERIFY_TIMEOUT:-300}" \
      "$BASH" "${root}/${path}" --self-test >/dev/null 2>&1 </dev/null
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "[exclusions] WARN C4 ${path}: --self-test now PASSES under $BASH — this exclusion is STALE, delete its ledger line"
      stale=$((stale + 1))
    fi
  done <<EOF
$(do_list)
EOF
  echo "[exclusions] verify: ${checked} excluded scripts exercised, ${stale} stale"
  return 0
}

# ============================================================
# --self-test
# ============================================================
_st_pass=0
_st_fail=0
_st_ck() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"; _st_pass=$((_st_pass + 1))
  else
    echo "FAIL: $name (got '$got' want '$want')"; _st_fail=$((_st_fail + 1))
  fi
}
_st_ck_has() {
  local name="$1" hay="$2" needle="$3"
  case "$hay" in
    *"$needle"*) echo "PASS: $name"; _st_pass=$((_st_pass + 1)) ;;
    *) echo "FAIL: $name (output lacked '$needle'; got: $hay)"; _st_fail=$((_st_fail + 1)) ;;
  esac
}

do_self_test() {
  local tmp root real out rc
  tmp="$(mktemp -d 2>/dev/null || echo "/tmp/nl-excl-st-$$")"; mkdir -p "$tmp"
  root="$(resolve_repo_root)" || { echo "self-test: repo root unresolvable"; echo "self-test: FAIL"; exit 1; }
  real="${root}/adapters/claude-code/config/selftest-sweep-exclusions.txt"

  # ---- S1 (REAL ARTIFACT, not a hand-written fixture): the shipped ledger
  # parses and passes every structural control. This is the oracle that
  # matters — a parser proven only against fixtures its author wrote has
  # masked Critical defects in this repo before.
  out="$(NL_SELFTEST_EXCLUSIONS_FILE="$real" do_check 2>&1)"; rc=$?
  _st_ck "S1 real shipped ledger passes --check" "$rc" "0"
  _st_ck_has "S1 --check reports the entry count" "$out" "[exclusions] OK"

  # ---- S2 (REAL ARTIFACT): --list on the shipped ledger yields ONLY paths,
  # no comment lines, no reason text, and every path resolves on disk.
  local listed n bad
  listed="$(NL_SELFTEST_EXCLUSIONS_FILE="$real" do_list)"
  n="$(printf '%s\n' "$listed" | grep -c '[^[:space:]]')"
  _st_ck "S2 real ledger lists 2 excluded paths" "$n" "2"
  bad=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in *' '*|*'#'*) bad=$((bad + 1)) ;; esac
    [ -f "${root}/${p}" ] || bad=$((bad + 1))
  done <<EOF
$listed
EOF
  _st_ck "S2 every listed path is bare and exists on disk" "$bad" "0"

  # ---- S3 (REAL ARTIFACT): the two paths the M6 disposition excluded are the
  # two paths in the ledger — the disposition and the mechanism agree.
  _st_ck_has "S3 lists attic/decision-context-gate.sh" "$listed" "adapters/claude-code/attic/decision-context-gate.sh"
  _st_ck_has "S3 lists attic/workstreams-extract-pending.sh" "$listed" "adapters/claude-code/attic/workstreams-extract-pending.sh"

  # ---- S4 (REAL ARTIFACT): the script M6 FIXED is NOT excluded. This is the
  # control that stops the ledger from quietly growing to cover a fixable
  # script — the "blanket they're attic, ignore" outcome M6 forbids.
  case "$listed" in
    *workstreams-state-gate.sh*)
      echo "FAIL: S4 attic/workstreams-state-gate.sh is excluded but M6 FIXED it"; _st_fail=$((_st_fail + 1)) ;;
    *)
      echo "PASS: S4 the fixed script (attic/workstreams-state-gate.sh) is not excluded"; _st_pass=$((_st_pass + 1)) ;;
  esac

  # ---- S5 RED fixture: C1, a ledger line naming a path that does not exist.
  printf '%s\n' "adapters/claude-code/attic/no-such-file-abcdef.sh  a reason long enough to clear the forty character minimum bar" > "$tmp/c1.txt"
  out="$(NL_SELFTEST_EXCLUSIONS_FILE="$tmp/c1.txt" do_check 2>&1)"; rc=$?
  _st_ck "S5 C1 missing path -> exit 1" "$rc" "1"
  _st_ck_has "S5 C1 names the control" "$out" "RED C1"

  # ---- S6 RED fixture: C2, a reason under the minimum.
  printf '%s\n' "adapters/claude-code/attic/decision-context-gate.sh  flaky" > "$tmp/c2.txt"
  out="$(NL_SELFTEST_EXCLUSIONS_FILE="$tmp/c2.txt" do_check 2>&1)"; rc=$?
  _st_ck "S6 C2 short reason -> exit 1" "$rc" "1"
  _st_ck_has "S6 C2 names the control" "$out" "RED C2"

  # ---- S7 RED fixture: C3, an attempt to silence a LIVE hook.
  printf '%s\n' "adapters/claude-code/hooks/harness-doctor.sh  a reason long enough to clear the forty character minimum bar" > "$tmp/c3.txt"
  out="$(NL_SELFTEST_EXCLUSIONS_FILE="$tmp/c3.txt" do_check 2>&1)"; rc=$?
  _st_ck "S7 C3 live hooks/ path -> exit 1" "$rc" "1"
  _st_ck_has "S7 C3 names the control" "$out" "RED C3"

  # ---- S8 RED fixture: C3 also covers the live scripts/ surface.
  printf '%s\n' "adapters/claude-code/scripts/health-tick.sh  a reason long enough to clear the forty character minimum bar" > "$tmp/c3b.txt"
  out="$(NL_SELFTEST_EXCLUSIONS_FILE="$tmp/c3b.txt" do_check 2>&1)"; rc=$?
  _st_ck "S8 C3 live scripts/ path -> exit 1" "$rc" "1"

  # ---- S9 GREEN fixture: comments and blank lines are ignored, not parsed
  # as entries (the classic ledger-parser defect).
  {
    echo "# a comment naming adapters/claude-code/hooks/harness-doctor.sh which must NOT be read as an entry"
    echo ""
    echo "   # an indented comment"
    echo "adapters/claude-code/attic/decision-context-gate.sh  a reason long enough to clear the forty character minimum bar"
  } > "$tmp/green.txt"
  out="$(NL_SELFTEST_EXCLUSIONS_FILE="$tmp/green.txt" do_check 2>&1)"; rc=$?
  _st_ck "S9 comments/blanks ignored -> exit 0" "$rc" "0"
  out="$(NL_SELFTEST_EXCLUSIONS_FILE="$tmp/green.txt" do_list)"
  _st_ck "S9 comment lines are not listed as paths" "$(printf '%s\n' "$out" | grep -c '[^[:space:]]')" "1"

  # ---- S10: an absent ledger means "nothing excluded", never "sweep nothing".
  out="$(NL_SELFTEST_EXCLUSIONS_FILE="$tmp/does-not-exist.txt" do_list)"; rc=$?
  _st_ck "S10 absent ledger -> --list exits 0" "$rc" "0"
  _st_ck "S10 absent ledger -> --list is empty" "$(printf '%s' "$out" | wc -c | tr -d ' ')" "0"
  out="$(NL_SELFTEST_EXCLUSIONS_FILE="$tmp/does-not-exist.txt" do_check 2>&1)"; rc=$?
  _st_ck "S10 absent ledger -> --check exits 0 with a WARN" "$rc" "0"
  _st_ck_has "S10 absent ledger WARNs" "$out" "WARN ledger absent"

  # ---- S11 (REAL ARTIFACT, C4): both excluded scripts must STILL FAIL their
  # own --self-test under THIS interpreter. Run directly here rather than
  # through do_verify so the assertion is on the real exit codes.
  local p stale=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    HARNESS_SELFTEST=1 nl_run_bounded "${NL_EXCLUSIONS_VERIFY_TIMEOUT:-300}" \
      "$BASH" "${root}/${p}" --self-test >/dev/null 2>&1 </dev/null
    [ $? -eq 0 ] && stale=$((stale + 1))
  done <<EOF
$listed
EOF
  _st_ck "S11 both excluded scripts still fail under $BASH (0 stale)" "$stale" "0"

  # ---- S12 (REAL ARTIFACT): the M6 FIX holds — attic/workstreams-state-gate.sh
  # passes its own self-test under THIS interpreter. If the attic/lib/
  # waiver-purpose-clause.sh shim is ever removed this goes RED.
  HARNESS_SELFTEST=1 nl_run_bounded "${NL_EXCLUSIONS_VERIFY_TIMEOUT:-300}" \
    "$BASH" "${root}/adapters/claude-code/attic/workstreams-state-gate.sh" --self-test >/dev/null 2>&1 </dev/null
  _st_ck "S12 M6-fixed attic/workstreams-state-gate.sh passes under $BASH" "$?" "0"

  rm -rf "$tmp" 2>/dev/null || true
  echo
  echo "self-test summary: ${_st_pass} passed, ${_st_fail} failed"
  [ "$_st_fail" -eq 0 ] || return 1
  return 0
}

# ============================================================
# main
# ============================================================
case "${1:---list}" in
  --list)      do_list ;;
  --check)     do_check ;;
  --verify)    do_verify ;;
  --path)      ledger_path ;;
  --self-test) do_self_test ;;
  -h|--help)
    echo "usage: selftest-sweep-exclusions.sh [--list|--check|--verify|--path|--self-test]"
    echo "  --list      repo-relative excluded paths, one per line (the sweep-runner API)"
    echo "  --check     C1 path exists / C2 reason >=${MIN_REASON_CHARS} chars / C3 not a live surface; exit 1 on RED"
    echo "  --verify    C4 every excluded script's --self-test still fails; WARN when stale"
    echo "  --path      print the ledger file path"
    echo "  --self-test this script's own suite"
    ;;
  *)
    echo "selftest-sweep-exclusions.sh: unknown mode '$1'" >&2
    exit 2
    ;;
esac
