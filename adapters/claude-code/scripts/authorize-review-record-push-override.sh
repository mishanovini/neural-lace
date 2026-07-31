#!/bin/bash
# authorize-review-record-push-override.sh — OPERATOR-FACING emergency
# authorization for hooks/review-record-push-gate.sh (the AUTHORITATIVE
# pre-push review-coverage gate; adapters/claude-code/doctrine/
# deterministic-process.md).
#
# WHY THIS EXISTS (Rule 2 — "an override the actor authors unilaterally is
# not an override"): review-record-commit-gate.sh's REVIEW_RECORD_GATE_
# OVERRIDE is an inline env var an agent can set in the SAME command it is
# authorizing, with no operator authorization checked anywhere — measured
# 2026-07-29/30 at 78 uses, none of them operator-initiated. That is
# sufficient for the commit-time gate now that it is advisory-only, but NOT
# sufficient at the authoritative layer (push). This script is the
# authorization ARTIFACT the acting agent cannot produce for itself in one
# step: it is a SEPARATE prior invocation, writes a marker file, and the
# gate consumes it — the same shape as /grant-local-edit (rules/
# local-edit-authorization.md), mirrored deliberately.
#
# TRUST MODEL (stated plainly, same honesty bar as /grant-local-edit's own
# SKILL.md): this is NOT a claim of cryptographic non-forgeability — an
# agent with shell access to ~/.claude/state/ could in principle write a
# matching marker by hand. What this DOES add over an inline env var:
#   - a SEPARATE tool call, distinguishable in an audit trail from the push
#     it authorizes (not glued onto the same command);
#   - SHA-SCOPING: the marker names the exact commit it authorizes, so it
#     cannot be replayed against a later, unrelated push;
#   - a 900-second TTL (tighter than /grant-local-edit's 30 min — a push is
#     a one-shot action, not a sustained editing session);
#   - the SAME reason validation (>=20 chars, non-placeholder) the gate
#     re-checks independently at consumption time.
# Per this harness's own operating rules, invoking this script is
# authorized ONLY when the OPERATOR's own message in the current turn
# explicitly requests the override — never on an agent's initiative, and
# never to land the agent's own unreviewed work. That boundary is a
# behavioral rule (same as /grant-local-edit's), not a technical one this
# script can enforce by itself.
#
# USAGE (operator-facing — this is the exact command a push-gate block
# message prints):
#   bash adapters/claude-code/scripts/authorize-review-record-push-override.sh \
#     "<reason>" [--sha <sha>]
#
# <reason>  required, >=20 chars, not a placeholder ("test"/"skip"/"bypass"/...).
# --sha     optional; defaults to the current repo's HEAD.
#
# Writes: ~/.claude/state/review-record-push-override-<full-sha>-<ISO8601>.txt
# (override via REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR, same convention the
# gate reads).
#
# Self-test: bash authorize-review-record-push-override.sh --self-test

set -u

_ARPO_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

_arpo_state_dir() {
  if [[ -n "${REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR:-}" ]]; then
    printf '%s' "$REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR"
  elif [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s' "${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}/authorize-review-record-push-override-selftest/$$}/state"
  else
    printf '%s' "$HOME/.claude/state"
  fi
}

_arpo_usage() {
  cat >&2 <<'EOF'
Usage: authorize-review-record-push-override.sh "<reason>" [--sha <sha>]

Authorizes review-record-push-gate.sh to allow ONE push of the given commit
(default: current HEAD of the repo you run this from) despite unreviewed
in-surface content, because the operator has decided the push cannot wait
for review.

Invoke ONLY on the OPERATOR'S OWN explicit authorization in the current
chat turn — never on an agent's own initiative, and never to land an
agent's own unreviewed work. See this file's header comment and
adapters/claude-code/doctrine/deterministic-process.md Rule 2.

<reason> must be a substantive sentence (>=20 chars, not a placeholder like
"test"/"skip"/"bypass") explaining why the push cannot wait for review.

The marker expires in 900s (15 min) and authorizes a push of the EXACT sha
it was written for only — it does not open a general bypass window.
EOF
}

_arpo_main() {
  if [[ $# -eq 0 ]]; then _arpo_usage; return 2; fi
  local reason="$1"; shift
  local sha=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sha) shift; sha="${1:-}"; shift ;;
      *) shift ;;
    esac
  done

  local lib="$_ARPO_SELF_DIR/../hooks/lib/review-record-gate-lib.sh"
  if [[ ! -f "$lib" ]]; then
    echo "authorize-review-record-push-override: cannot find review-record-gate-lib.sh at $lib -- aborting" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$lib" 2>/dev/null || {
    echo "authorize-review-record-push-override: cannot load review-record-gate-lib.sh -- aborting" >&2
    return 1
  }
  command -v rrg_validate_waiver_reason >/dev/null 2>&1 || {
    echo "authorize-review-record-push-override: rrg_validate_waiver_reason unavailable after sourcing the lib -- aborting" >&2
    return 1
  }

  if ! rrg_validate_waiver_reason "$reason"; then
    echo "authorize-review-record-push-override: reason rejected -- must be >=20 chars and not a placeholder (got: \"$reason\")" >&2
    return 1
  fi

  if [[ -z "$sha" ]]; then
    sha="$(git rev-parse HEAD 2>/dev/null)" || {
      echo "authorize-review-record-push-override: not in a git repo and no --sha given" >&2
      return 1
    }
  fi
  local full_sha
  full_sha="$(git rev-parse --verify "$sha" 2>/dev/null)" || {
    echo "authorize-review-record-push-override: '$sha' does not resolve to a commit here" >&2
    return 1
  }

  local dir; dir="$(_arpo_state_dir)"
  mkdir -p "$dir" 2>/dev/null || {
    echo "authorize-review-record-push-override: cannot create state dir $dir" >&2
    return 1
  }
  local ts; ts="$(date -u +%Y-%m-%dT%H-%M-%SZ 2>/dev/null || echo unknown)"
  local marker="$dir/review-record-push-override-${full_sha}-${ts}.txt"
  local repo_root; repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo unknown)"
  {
    printf 'SHA: %s\n' "$full_sha"
    printf 'Granted: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    printf 'Reason: %s\n' "$reason"
    printf 'Repo: %s\n' "$repo_root"
  } > "$marker"

  echo "authorize-review-record-push-override: granted for $full_sha (expires in 900s)." >&2
  echo "  marker: $marker" >&2
  echo "  Retry your push now -- review-record-push-gate.sh will honor this for THIS commit only." >&2
  return 0
}

# ===========================================================================
# Self-test
# ===========================================================================
_arpo_self_test() {
  local PASS=0 FAIL=0
  pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
  fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }

  local T; T="$(mktemp -d)" || { echo "cannot mktemp"; return 1; }
  local SELF="$_ARPO_SELF_DIR/$(basename "${BASH_SOURCE[0]}")"

  local R="$T/repo"
  mkdir -p "$R"
  ( cd "$R" && git init -q . && git config user.email t@example.com && git config user.name T \
      && git config core.hooksPath "" && echo a > a && git add a && git commit -qm init ) >/dev/null 2>&1
  local HEAD_SHA; HEAD_SHA="$(cd "$R" && git rev-parse HEAD)"

  echo "Scenario 1: no args -> usage + rc 2"
  local rc; rc="$( ( cd "$R" && bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "2" ]] && pass "no-args usage exit (rc=2)" || fail "expected rc 2, got $rc"

  echo "Scenario 2: substantive reason -> marker written with correct SHA + reason"
  local STATE="$T/state2"
  rc="$( ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE" bash "$SELF" "production is down and this cannot wait for review" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "valid reason accepted (rc=0)" || fail "valid reason rejected (rc=$rc)"
  local marker; marker="$(ls "$STATE"/review-record-push-override-"${HEAD_SHA}"-*.txt 2>/dev/null | head -1)"
  if [[ -n "$marker" && -f "$marker" ]]; then
    pass "marker written under the current HEAD sha"
  else
    fail "no marker found for HEAD sha $HEAD_SHA in $STATE"
  fi
  if grep -q "^Reason: production is down and this cannot wait for review$" "$marker" 2>/dev/null; then
    pass "marker contains the exact reason"
  else
    fail "marker reason content wrong or missing"
  fi

  echo "Scenario 3: short reason -> rejected, no marker"
  local STATE3="$T/state3"
  rc="$( ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE3" bash "$SELF" "short" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "short reason rejected (rc=1)" || fail "short reason accepted (rc=$rc)"
  if [[ -d "$STATE3" ]] && ls "$STATE3"/review-record-push-override-*.txt >/dev/null 2>&1; then
    fail "a marker was written despite a rejected reason"
  else
    pass "no marker written for a rejected reason"
  fi

  echo "Scenario 4: placeholder reason -> rejected"
  rc="$( ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$T/state4" bash "$SELF" "bypass bypass bypass bypass" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "placeholder reason rejected (rc=1)" || fail "placeholder reason accepted (rc=$rc)"

  echo "Scenario 5: --sha override writes a marker for the NAMED sha, not HEAD"
  echo b > "$R/b"
  ( cd "$R" && git add -A && git commit -qm second ) >/dev/null 2>&1
  local SECOND_SHA; SECOND_SHA="$(cd "$R" && git rev-parse HEAD)"
  local STATE5="$T/state5"
  rc="$( ( cd "$R" && REVIEW_RECORD_PUSH_OVERRIDE_STATE_DIR="$STATE5" bash "$SELF" "production is down and this cannot wait for review" --sha "$HEAD_SHA" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "--sha override accepted (rc=0)" || fail "--sha override rejected (rc=$rc)"
  if ls "$STATE5"/review-record-push-override-"${HEAD_SHA}"-*.txt >/dev/null 2>&1; then
    pass "marker written for the NAMED --sha, not current HEAD ($SECOND_SHA)"
  else
    fail "marker not written for the named --sha"
  fi

  echo "Scenario 6: not a git repo, no --sha -> rejected"
  rc="$( ( cd "$T" && bash "$SELF" "production is down and this cannot wait for review" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "1" ]] && pass "outside a repo with no --sha is rejected (rc=1)" || fail "should have been rejected (rc=$rc)"

  rm -rf "$T"
  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) export HARNESS_SELFTEST=1; _arpo_self_test; exit $? ;;
    *) _arpo_main "$@"; exit $? ;;
  esac
fi
