#!/usr/bin/env bash
# check-cross-repo-drift.sh — poll Neural Lace's two master SHAs and surface
# divergence. Drift detection component (b): periodic scheduled-task poller.
#
# WHY THIS EXISTS: per 2026-05-28 pivot (ADR-044 Reverted), the cross-repo
# mirror Action was dropped because the cross-account PAT operational burden
# was disproportionate to the actual use case (every push happens through
# Claude Code with the harness loaded, so a local check covers the
# steady-state need). This poller is the periodic backstop that surfaces
# drift even if no push happens for a while OR if a push by some other path
# bypassed `sync.sh`'s post-push verification (component a).
#
# Usage:
#   check-cross-repo-drift.sh              # check + report; exits 0/1/2
#   check-cross-repo-drift.sh --quiet      # silent on convergence; still
#                                          # reports + exits non-zero on drift
#   check-cross-repo-drift.sh --self-test  # built-in self-test
#
# Exit codes:
#   0  — both repos at identical SHA (or only one configured; no drift possible)
#   1  — DRIFT DETECTED (SHAs differ)
#   2  — CANNOT VERIFY (no repos configured / no gh CLI / API unreachable)
#
# Configuration (per-machine, gitignored — read at runtime, not committed):
#   File: ~/.claude/local/cross-repo-drift-pairs.txt
#   Format: one line per repo pair, fields separated by spaces:
#     <owner1/name1> <owner2/name2> [<label>]
#   Example:
#     Pocket-Technician/neural-lace mishanovini/neural-lace neural-lace
#   Lines starting with # are comments. Empty lines ignored.
#
# Alerting (optional, drift-only):
#   - If NTFY_URL + NTFY_TOPIC are set (env or per-machine config), drift
#     events POST a tiny notification per ADR-042 ntfy contract.
#   - Without ntfy, drift writes to stderr (caller's stdout/stderr handling).
#
# Designed to be invoked by:
#   - A scheduled task (per-machine cron / scheduled-tasks MCP server entry).
#   - A SessionStart hook companion (component c at hooks/cross-repo-drift-warn.sh
#     calls this script in --quiet mode).
#   - Manual operator check.
#
# Identity-free: no real org/user names in this committed script. Pairs live
# in ~/.claude/local/ (gitignored per harness-hygiene).

set -u

CONFIG_FILE="${CROSS_REPO_DRIFT_PAIRS:-$HOME/.claude/local/cross-repo-drift-pairs.txt}"
QUIET=0

# -------- argument parse --------
case "${1:-}" in
  --self-test|self-test) MODE="self-test" ;;
  --quiet|-q)            QUIET=1; MODE="run" ;;
  ""|--check|check)      MODE="run" ;;
  -h|--help)
    sed -n '2,40p' "$0"
    exit 0
    ;;
  *)
    echo "check-cross-repo-drift.sh: unknown argument '$1' (use --help)" >&2
    exit 2
    ;;
esac

# -------- ntfy alert (optional, drift-only) --------
_drift_notify() {
  local title="$1" body="$2"
  local ntfy_url="${NTFY_URL:-}"
  local ntfy_topic="${NTFY_TOPIC:-}"
  if [ -z "$ntfy_url" ] || [ -z "$ntfy_topic" ]; then
    # Try the per-machine config (read via existing read-local-config.sh if available).
    if [ -f "$HOME/.claude/local/ntfy.config.json" ] && command -v jq >/dev/null 2>&1; then
      ntfy_url="${ntfy_url:-$(jq -r '.url // empty' "$HOME/.claude/local/ntfy.config.json" 2>/dev/null)}"
      ntfy_topic="${ntfy_topic:-$(jq -r '.topic // empty' "$HOME/.claude/local/ntfy.config.json" 2>/dev/null)}"
    fi
  fi
  if [ -z "$ntfy_url" ] || [ -z "$ntfy_topic" ]; then
    return 0
  fi
  command -v curl >/dev/null 2>&1 || return 0
  curl -fsS -m 5 -H "Title: ${title}" -d "${body}" "${ntfy_url%/}/${ntfy_topic}" >/dev/null 2>&1 || true
}

# -------- core check --------
_drift_run() {
  command -v gh >/dev/null 2>&1 || {
    [ "$QUIET" = "0" ] && echo "check-cross-repo-drift: gh CLI not available; cannot verify." >&2
    return 2
  }

  if [ ! -f "$CONFIG_FILE" ]; then
    [ "$QUIET" = "0" ] && echo "check-cross-repo-drift: no config file at $CONFIG_FILE; nothing to check." >&2
    return 2
  fi

  local total=0 drifted=0 unverified=0 pair_line owner1 owner2 label sha1 sha2
  while IFS= read -r pair_line; do
    # Strip comments + leading/trailing whitespace.
    pair_line="${pair_line%%#*}"
    pair_line="${pair_line#"${pair_line%%[![:space:]]*}"}"
    pair_line="${pair_line%"${pair_line##*[![:space:]]}"}"
    [ -z "$pair_line" ] && continue

    # Parse: <owner1/name1> <owner2/name2> [<label>]
    # shellcheck disable=SC2086
    set -- $pair_line
    owner1="${1:-}"
    owner2="${2:-}"
    if [ -z "$owner1" ] || [ -z "$owner2" ]; then
      [ "$QUIET" = "0" ] && echo "  - malformed line, skipping: '$pair_line'" >&2
      continue
    fi
    label="${3:-${owner1}-vs-${owner2}}"

    total=$((total+1))
    # Use --jq to extract; then validate the result is a 40-char hex SHA. On a 404
    # `gh api` outputs the error JSON body to stdout (not blocked by --jq) and exits
    # non-zero — `|| true` suppresses the exit code, so we must validate the shape
    # explicitly to distinguish a real SHA from an error body.
    sha1="$(gh api "repos/${owner1}/branches/master" --jq '.commit.sha' 2>/dev/null || true)"
    sha2="$(gh api "repos/${owner2}/branches/master" --jq '.commit.sha' 2>/dev/null || true)"
    [[ "$sha1" =~ ^[0-9a-f]{40}$ ]] || sha1=""
    [[ "$sha2" =~ ^[0-9a-f]{40}$ ]] || sha2=""

    if [ -z "$sha1" ] || [ -z "$sha2" ]; then
      [ "$QUIET" = "0" ] && {
        echo "  - $label: CANNOT VERIFY"
        [ -z "$sha1" ] && echo "      $owner1 — SHA unavailable (auth scope / network / no master)"
        [ -z "$sha2" ] && echo "      $owner2 — SHA unavailable (auth scope / network / no master)"
      } >&2
      unverified=$((unverified+1))
      continue
    fi

    if [ "$sha1" = "$sha2" ]; then
      [ "$QUIET" = "0" ] && echo "  - $label: OK ($sha1)"
    else
      echo "" >&2
      echo "DRIFT DETECTED — $label" >&2
      echo "  $owner1 = $sha1" >&2
      echo "  $owner2 = $sha2" >&2
      drifted=$((drifted+1))
      _drift_notify "NL drift: $label" "$owner1=$sha1 vs $owner2=$sha2"
    fi
  done < "$CONFIG_FILE"

  if [ "$total" -eq 0 ]; then
    [ "$QUIET" = "0" ] && echo "check-cross-repo-drift: no repo pairs configured in $CONFIG_FILE." >&2
    return 2
  fi
  if [ "$drifted" -gt 0 ]; then
    return 1
  fi
  if [ "$unverified" -eq "$total" ]; then
    return 2
  fi
  return 0
}

# -------- self-test --------
_drift_self_test() {
  local tmp_cfg
  tmp_cfg="$(mktemp 2>/dev/null || mktemp -t 'drift-cfg')"
  [ -n "$tmp_cfg" ] || { echo "self-test: FAIL — could not create tmp file" >&2; return 1; }
  local passed=0 failed=0

  # ST1: empty/missing config -> exit 2.
  CONFIG_FILE="$tmp_cfg.nonexistent" QUIET=1 _drift_run; local rc=$?
  if [ "$rc" -eq 2 ]; then echo "self-test (1) missing-config-returns-2: PASS"; passed=$((passed+1)); else echo "self-test (1) missing-config-returns-2: FAIL (rc=$rc)" >&2; failed=$((failed+1)); fi

  # ST2: empty config (only comments) -> exit 2.
  printf '# comment only\n\n' > "$tmp_cfg"
  CONFIG_FILE="$tmp_cfg" QUIET=1 _drift_run; rc=$?
  if [ "$rc" -eq 2 ]; then echo "self-test (2) comments-only-returns-2: PASS"; passed=$((passed+1)); else echo "self-test (2) comments-only-returns-2: FAIL (rc=$rc)" >&2; failed=$((failed+1)); fi

  # ST3: malformed line (1 field) is skipped, still no pairs -> exit 2.
  printf 'just-one-field\n' > "$tmp_cfg"
  CONFIG_FILE="$tmp_cfg" QUIET=1 _drift_run; rc=$?
  if [ "$rc" -eq 2 ]; then echo "self-test (3) malformed-line-skipped: PASS"; passed=$((passed+1)); else echo "self-test (3) malformed-line-skipped: FAIL (rc=$rc)" >&2; failed=$((failed+1)); fi

  # ST4: well-formed config with unreachable repos -> unverified -> exit 2.
  # (Uses obviously-non-existent owner/name; gh api fails for both.)
  printf 'definitely-not-an-owner/definitely-not-a-repo other-fake-owner/other-fake-repo fake-pair\n' > "$tmp_cfg"
  CONFIG_FILE="$tmp_cfg" QUIET=1 _drift_run; rc=$?
  if [ "$rc" -eq 2 ]; then echo "self-test (4) unreachable-repos-returns-2: PASS"; passed=$((passed+1)); else echo "self-test (4) unreachable-repos-returns-2: FAIL (rc=$rc)" >&2; failed=$((failed+1)); fi

  # ST5: --quiet on missing config still returns 2 (silent path).
  out="$(CONFIG_FILE="$tmp_cfg.nonexistent" "$0" --quiet 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$out" ]; then echo "self-test (5) quiet-suppresses-stderr-on-no-config: PASS"; passed=$((passed+1)); else echo "self-test (5) quiet-suppresses-stderr-on-no-config: FAIL (rc=$rc, out='$out')" >&2; failed=$((failed+1)); fi

  rm -f "$tmp_cfg" 2>/dev/null || true

  echo ""
  if [ "$failed" -eq 0 ]; then
    echo "self-test summary: $passed passed, $failed failed (of $((passed+failed)) scenarios)"
    return 0
  else
    echo "self-test summary: $passed passed, $failed failed" >&2
    return 1
  fi
}

# -------- dispatch --------
case "$MODE" in
  self-test) _drift_self_test ;;
  run)       _drift_run ;;
esac
exit $?
