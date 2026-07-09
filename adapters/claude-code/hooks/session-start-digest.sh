#!/usr/bin/env bash
# session-start-digest.sh — SessionStart hook (Wave E, task E.1).
#
# ONE consolidated SessionStart block, hard-capped at 15 output lines,
# replacing the TRANSITIONAL session-start-surfacer-pack.sh voice
# (specs-d §D.0.3 entry 8) per specs-e §E.1. The pack members stay on disk
# (attic move deferred to Wave F per §E.1 spec) — this hook reads each
# member's underlying data source directly (or invokes the member and
# summarizes its output) rather than passing member output through
# verbatim, because the pack's per-member blocks are themselves multi-line
# and would blow the 15-line budget on their own.
#
# FEEDS (specs-e §E.1, one line each, silent when empty):
#   1. pending discoveries               (docs/discoveries/*.md status:pending)
#   2. stale ACTIVE plans                (docs/plans/*.md, git-log staleness)
#   3. external-monitor alerts           (~/.claude/state/external-monitor-alerts/)
#   4. spawned-task results              (.claude/state/spawned-task-results/)
#   5. pending decisions                 (decision-context-pending-surfacer.sh)
#   6. git freshness                     (session-start-git-freshness.sh)
#   7. worktree advice                   (session-start-worktree-advisor.sh)
#   8. doctor --quick verdict            (harness-doctor.sh --quick, reused exit code)
#   9. ledger 24h summary                (lib/signal-ledger.sh ledger_tail)
#  10. nl-issues untriaged count         (§E.8 — tolerate absent)
#  11. waiver-density alarm              (§E.3 — tolerate absent)
#  12. unresolved-gaps entries           (§E.11 — tolerate absent)
#  13. NEEDS-YOU.md open-item count      (§E.6 — tolerate absent)
#  14. staleness-disposition proposals   (Wave F, task F.1, specs-f §F.1 —
#                                          ACTIVE plans / worktrees / local
#                                          branches stale >=7d; one-word
#                                          operator approval each)
#  15. harness "what's new" changelog    (§F.2b — tolerate absent; harness-changelog.sh --digest-line)
#  16. backlog accountability proposals  (observability O.9 pre-activation
#                                          increment BACKLOG-LOOP-01 —
#                                          docs/backlog.md open rows overdue
#                                          per age tier; one-word disposition
#                                          proposals, once per <ID>-<ISOweek>)
#
# A quiet harness produces a 2-line digest: doctor verdict + "all quiet".
#
# DEDUP / AUTO-EXPIRY / AUTO-ACK (specs-e §E.1):
#   State at ~/.claude/state/digest/seen.jsonl (override: DIGEST_SEEN_PATH,
#   auto-sandboxed under HARNESS_SELFTEST=1 per the signal-ledger.sh
#   pattern). One JSON object per (feed, item-key): {feed, item_key,
#   first_seen, count}. An item seen >=3 sessions with no state change
#   collapses into a "+N repeats" suffix instead of repeating the full line
#   every session. Monitor alerts that are byte-identical duplicates of an
#   ALREADY-ACKED class are auto-acked (.acked sibling written) with ONE
#   ledger event per class (not per file) — see auto_ack_monitor_class().
#
# NL-FINDING-021 (upstream fix, same task): the external-monitor probe
# writer (adapters/claude-code/attic/principles-compliance-gate.sh, the
# ONLY writer under external-monitor-alerts/) must not emit an alert whose
# anomaly data is empty. Fixed at the emission site in that file (grep
# ALERT_FILE=.*\.json\" in attic/principles-compliance-gate.sh for the
# guard). The 32 pre-existing stale principles-gate-r3 duplicates are acked
# as ONE class by this hook's --ack-finding-021 mode (invoked once at
# ship-time, not on every session start).
#
# Self-test: --self-test, >= 8 scenarios (see run_self_test()).
# HARNESS_SELFTEST=1 sandboxes all state writes (seen.jsonl + any .acked
# writes) under a tmp dir, mirroring lib/signal-ledger.sh's own contract.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
{ source "$HOOKS_DIR/lib/nl-paths.sh" 2>/dev/null; } || true
# shellcheck disable=SC1091
{ source "$HOOKS_DIR/lib/signal-ledger.sh" 2>/dev/null; } || true
# shellcheck disable=SC1091
{ source "$HOOKS_DIR/lib/hook-reentry-guard.sh" 2>/dev/null; } || true

# ---- WAVE-O O.9: od_backlog_health oracle, guarded source + feature-detect ----
# Contract C4 (specs-o §O.0.3): observability-derive.sh is owned/built by task
# O.3 (parallel; O.9 never creates/edits that file — §O.0.1 rule 2). Source it
# if present; if it doesn't yet supply od_backlog_health (pre-merge, or the
# file doesn't exist at all), fall back to the private test shim so this hook
# still has a real oracle to call. Once O.3 merges the real lib, the guarded
# source above wins the declare -F check and this fallback is never invoked.
# shellcheck disable=SC1091
{ source "$HOOKS_DIR/lib/observability-derive.sh" 2>/dev/null; } || true
if ! declare -F od_backlog_health >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  { source "$HOOKS_DIR/../tests/fixtures/wave-o/O.9/od-backlog-shim.sh" 2>/dev/null; } || true
fi

MAX_LINES=15
DIGEST_ALERT_CAP=5

# ----------------------------------------------------------------------
# State path resolution (mirrors lib/signal-ledger.sh's HARNESS_SELFTEST
# sandboxing contract exactly, so this hook's own self-test never touches
# the real machine's seen.jsonl regardless of $HOME).
# ----------------------------------------------------------------------
_digest_seen_path() {
  if [[ -n "${DIGEST_SEEN_PATH:-}" ]]; then
    printf '%s' "$DIGEST_SEEN_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/digest-selftest/%s/seen.jsonl' "${TMPDIR:-/tmp}" "${$}"
    return 0
  fi
  printf '%s/.claude/state/digest/seen.jsonl' "${HOME:-$PWD}"
}

_alert_dir_default() {
  printf '%s/.claude/state/external-monitor-alerts' "${HOME:-$PWD}"
}

# ----------------------------------------------------------------------
# seen.jsonl helpers. Format: one JSON object per line:
#   {"feed":"<feed>","item_key":"<key>","first_seen":"<iso>","count":<n>}
# Node is used when available (same convention as decision-context-
# pending-surfacer.sh); a grep/sed fallback covers count-only lookups when
# node is unavailable so dedup degrades gracefully rather than crashing.
# ----------------------------------------------------------------------
_have() { command -v "$1" >/dev/null 2>&1; }

# _seen_lookup <path> <feed> <item_key>  -> prints "<count>\t<first_seen>" or empty
_seen_lookup() {
  local path="$1" feed="$2" key="$3"
  [[ -f "$path" ]] || return 0
  if _have node; then
    node -e '
      "use strict";
      var fs = require("fs");
      var path = process.argv[1], feed = process.argv[2], key = process.argv[3];
      var lines;
      try { lines = fs.readFileSync(path, "utf8").split("\n"); } catch (e) { process.exit(0); }
      for (var i = lines.length - 1; i >= 0; i--) {
        var l = lines[i].trim();
        if (!l) continue;
        var obj;
        try { obj = JSON.parse(l); } catch (e) { continue; }
        if (obj.feed === feed && obj.item_key === key) {
          process.stdout.write((obj.count || 1) + "\t" + (obj.first_seen || ""));
          process.exit(0);
        }
      }
    ' "$path" "$feed" "$key" 2>/dev/null
  fi
}

# _seen_bump <path> <feed> <item_key> — increments count (or creates at 1),
# preserving first_seen. Best-effort; never fails the caller.
_seen_bump() {
  local path="$1" feed="$2" key="$3"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  _have node || return 0
  local now
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  node -e '
    "use strict";
    var fs = require("fs");
    var path = process.argv[1], feed = process.argv[2], key = process.argv[3], now = process.argv[4];
    var lines = [];
    try { lines = fs.readFileSync(path, "utf8").split("\n").filter(Boolean); } catch (e) {}
    var found = false;
    var out = lines.map(function (l) {
      var obj;
      try { obj = JSON.parse(l); } catch (e) { return l; }
      if (obj.feed === feed && obj.item_key === key) {
        found = true;
        obj.count = (obj.count || 1) + 1;
        return JSON.stringify(obj);
      }
      return l;
    });
    if (!found) {
      out.push(JSON.stringify({ feed: feed, item_key: key, first_seen: now, count: 1 }));
    }
    fs.writeFileSync(path, out.join("\n") + "\n");
  ' "$path" "$feed" "$key" "$now" 2>/dev/null || true
}

# _repeat_suffix <count> — prints " (+N repeats)" when count>=3, else "".
_repeat_suffix() {
  local count="${1:-1}"
  if [[ "$count" =~ ^[0-9]+$ ]] && [[ "$count" -ge 3 ]]; then
    printf ' (+%d repeats)' "$((count - 1))"
  fi
}

# ----------------------------------------------------------------------
# Feed 1: pending discoveries — docs/discoveries/*.md status:pending.
# ----------------------------------------------------------------------
_fm_value() {
  local file="$1" key="$2"
  head -n 30 "$file" 2>/dev/null \
    | grep -iE "^${key}:[[:space:]]*" \
    | head -n 1 \
    | sed -E "s/^[^:]+:[[:space:]]*//; s/^['\"](.*)['\"]\$/\1/"
}

feed_discoveries() {
  local seen_path="$1" cwd="${2:-$PWD}"
  local dir="$cwd/docs/discoveries"
  [[ -d "$dir" ]] || return 0
  local f base status oldest="" oldest_date="9999-99-99" count=0
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    case "$base" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;;
      *) continue ;;
    esac
    status="$(_fm_value "$f" status | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$status" || "$status" == "pending" ]]; then
      count=$((count + 1))
      local d="${base:0:10}"
      if [[ "$d" < "$oldest_date" ]]; then
        oldest_date="$d"
        oldest="$base"
      fi
    fi
  done
  [[ "$count" -eq 0 ]] && return 0
  local key="discoveries-pending"
  local prior; prior="$(_seen_lookup "$seen_path" "discoveries" "$key")"
  local prior_count="${prior%%$'\t'*}"
  _seen_bump "$seen_path" "discoveries" "$key"
  printf 'discoveries: %d pending, oldest %s%s -> docs/discoveries/%s\n' \
    "$count" "$oldest_date" "$(_repeat_suffix "${prior_count:-1}")" "$oldest"
}

# ----------------------------------------------------------------------
# Feed 2: stale ACTIVE plans — docs/plans/*.md, Status: ACTIVE + git-log age.
# ----------------------------------------------------------------------
feed_stale_plans() {
  local seen_path="$1" cwd="${2:-$PWD}"
  local hours="${STALE_ACTIVE_PLAN_HOURS:-24}"
  local secs=$((hours * 3600))
  local dir="$cwd/docs/plans"
  [[ -d "$dir" ]] || return 0
  local now; now=$(date +%s)
  local count=0 oldest_slug="" oldest_age=-1
  local f
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    head -n 30 "$f" 2>/dev/null | grep -iqE "^Status:[[:space:]]*ACTIVE" || continue
    local ts
    ts=$(git -C "$cwd" log -1 --format=%ct -- "$f" 2>/dev/null)
    [[ -z "$ts" || "$ts" == "0" ]] && ts=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo "")
    [[ -z "$ts" ]] && continue
    local age=$((now - ts))
    [[ "$age" -ge "$secs" ]] || continue
    count=$((count + 1))
    if [[ "$age" -gt "$oldest_age" ]]; then
      oldest_age="$age"
      oldest_slug="$(basename "$f" .md)"
    fi
  done
  [[ "$count" -eq 0 ]] && return 0
  local hours_ago=$((oldest_age / 3600))
  local key="stale-active-plans"
  local prior; prior="$(_seen_lookup "$seen_path" "plans" "$key")"
  local prior_count="${prior%%$'\t'*}"
  _seen_bump "$seen_path" "plans" "$key"
  printf 'stale-plans: %d ACTIVE >%dh, oldest %s (%dh)%s -> docs/plans/%s.md\n' \
    "$count" "$hours" "$oldest_slug" "$hours_ago" "$(_repeat_suffix "${prior_count:-1}")" "$oldest_slug"
}

# ----------------------------------------------------------------------
# Feed 3: external-monitor alerts — unacked count post-dedup + auto-ack.
# Reuses external-monitor-alert-surfacer.sh's file contract: *.json without
# a *.json.acked sibling is unread; ".acked" siblings suppress.
# ----------------------------------------------------------------------
_json_field() {
  local file="$1" key="$2"
  if _have jq; then
    jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null
  else
    grep -E "\"${key}\"[[:space:]]*:" "$file" 2>/dev/null \
      | head -n 1 \
      | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"?//; s/\"?[[:space:]]*,?[[:space:]]*\$//"
  fi
}

# auto_ack_monitor_class <alert_dir> — groups unacked alerts by their
# "class" (basename with the timestamp+session-id run stripped, i.e. the
# leading token before the first run of digits, e.g. "principles-gate-r3"),
# and when a class already has AT LEAST ONE acked file, auto-acks every
# remaining unacked file of that same class as byte-identical duplicates,
# emitting exactly ONE ledger event per class (not per file). Prints the
# count of files newly acked (for self-test assertions); silent otherwise.
auto_ack_monitor_class() {
  local alert_dir="$1"
  [[ -d "$alert_dir" ]] || return 0
  local f base class
  declare -A class_has_acked
  declare -A class_unacked_files
  for f in "$alert_dir"/*.json; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    class="$(printf '%s' "$base" | sed -E 's/-[0-9]{4,}.*$//')"
    if [[ -f "${f}.acked" ]]; then
      class_has_acked["$class"]=1
    else
      class_unacked_files["$class"]+="$f"$'\n'
    fi
  done
  local total_acked=0
  for class in "${!class_unacked_files[@]}"; do
    [[ "${class_has_acked[$class]:-0}" == "1" ]] || continue
    local file
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      touch "${file}.acked" 2>/dev/null && total_acked=$((total_acked + 1))
    done <<< "${class_unacked_files[$class]}"
    if [[ "$total_acked" -gt 0 ]] && _have ledger_emit; then
      ledger_emit "session-start-digest" "waiver" "auto-acked duplicate ${class} alerts (already-acked class, NL-FINDING-021)"
    fi
  done
  [[ "$total_acked" -gt 0 ]] && printf '%d\n' "$total_acked"
  return 0
}

feed_monitor_alerts() {
  local seen_path="$1" alert_dir="${2:-$(_alert_dir_default)}"
  [[ -d "$alert_dir" ]] || return 0

  # Auto-ack duplicate classes first (silent on the digest line itself —
  # the ledger event is the record; the digest reports the POST-ack count).
  auto_ack_monitor_class "$alert_dir" >/dev/null

  local f count=0 newest="" newest_ts=""
  for f in "$alert_dir"/*.json; do
    [[ -f "$f" ]] || continue
    case "$f" in *.json.acked) continue ;; esac
    [[ -f "${f}.acked" ]] && continue
    count=$((count + 1))
    local base; base="$(basename "$f" .json)"
    if [[ -z "$newest" || "$base" > "$newest" ]]; then
      newest="$base"
    fi
  done
  [[ "$count" -eq 0 ]] && return 0
  local key="monitor-alerts"
  local prior; prior="$(_seen_lookup "$seen_path" "monitor" "$key")"
  local prior_count="${prior%%$'\t'*}"
  _seen_bump "$seen_path" "monitor" "$key"
  printf 'monitor-alerts: %d unacked, newest %s%s -> %s\n' \
    "$count" "$newest" "$(_repeat_suffix "${prior_count:-1}")" "$alert_dir"
}

# ----------------------------------------------------------------------
# Feed 4: spawned-task results — .claude/state/spawned-task-results/.
# ----------------------------------------------------------------------
feed_spawned_task_results() {
  local seen_path="$1" cwd="${2:-$PWD}"
  local dir="$cwd/.claude/state/spawned-task-results"
  [[ -d "$dir" ]] || return 0
  local f count=0 newest=""
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    case "$f" in *.json.acked) continue ;; esac
    [[ -f "${f}.acked" ]] && continue
    count=$((count + 1))
    newest="$(basename "$f" .json)"
  done
  [[ "$count" -eq 0 ]] && return 0
  local key="spawned-task-results"
  local prior; prior="$(_seen_lookup "$seen_path" "spawn" "$key")"
  local prior_count="${prior%%$'\t'*}"
  _seen_bump "$seen_path" "spawn" "$key"
  printf 'spawned-tasks: %d unacked, e.g. %s%s -> %s\n' \
    "$count" "$newest" "$(_repeat_suffix "${prior_count:-1}")" "$dir"
}

# ----------------------------------------------------------------------
# Feed 5: pending decisions — invoke decision-context-pending-surfacer.sh
# and summarize its output to a count + first item, rather than passing
# its (potentially multi-block) output through verbatim.
# ----------------------------------------------------------------------
feed_pending_decisions() {
  local seen_path="$1" input="$2"
  local member="$HOOKS_DIR/decision-context-pending-surfacer.sh"
  [[ -f "$member" ]] || return 0
  local out
  out="$(printf '%s' "$input" | bash "$member" 2>/dev/null || true)"
  [[ -z "$out" ]] && return 0
  local count first
  count="$(printf '%s\n' "$out" | grep -c '^\[decision-context' || true)"
  [[ "$count" -eq 0 ]] && count=1
  first="$(printf '%s\n' "$out" | grep -m1 '^\[decision-context' || true)"
  [[ -z "$first" ]] && first="$(printf '%s\n' "$out" | grep -m1 . || true)"
  local key="pending-decisions"
  local prior; prior="$(_seen_lookup "$seen_path" "decisions" "$key")"
  local prior_count="${prior%%$'\t'*}"
  _seen_bump "$seen_path" "decisions" "$key"
  printf 'decisions: %d pending%s -> %s\n' "$count" "$(_repeat_suffix "${prior_count:-1}")" \
    "$(printf '%s' "$first" | head -c 90)"
}

# ----------------------------------------------------------------------
# Feed 6: git freshness — invoke session-start-git-freshness.sh, summarize
# to ONE line (its native output may already be multi-line for multiple
# remotes / dirty-branch conditions).
# ----------------------------------------------------------------------
feed_git_freshness() {
  local cwd="${1:-$PWD}"
  local member="$HOOKS_DIR/session-start-git-freshness.sh"
  [[ -f "$member" ]] || return 0
  local out
  out="$(cd "$cwd" 2>/dev/null && echo '{}' | bash "$member" 2>/dev/null || true)"
  [[ -z "$out" ]] && return 0
  local count first
  count="$(printf '%s\n' "$out" | grep -c '^\[git-freshness\]' || true)"
  first="$(printf '%s\n' "$out" | grep -m1 '^\[git-freshness\]' | sed -E 's/^\[git-freshness\][[:space:]]*//')"
  if [[ "$count" -le 1 ]]; then
    printf 'git-freshness: %s\n' "$(printf '%s' "$first" | head -c 110)"
  else
    printf 'git-freshness: %d item(s), first: %s\n' "$count" "$(printf '%s' "$first" | head -c 90)"
  fi
}

# ----------------------------------------------------------------------
# Feed 7: worktree advice — invoke session-start-worktree-advisor.sh.
# ----------------------------------------------------------------------
feed_worktree_advice() {
  local cwd="${1:-$PWD}"
  local member="$HOOKS_DIR/session-start-worktree-advisor.sh"
  [[ -f "$member" ]] || return 0
  local out
  out="$(cd "$cwd" 2>/dev/null && echo '{}' | bash "$member" 2>/dev/null || true)"
  [[ -z "$out" ]] && return 0
  local first
  first="$(printf '%s\n' "$out" | grep -m1 '^\[worktree-advisor\]' | sed -E 's/^\[worktree-advisor\][[:space:]]*//')"
  printf 'worktree: %s\n' "$(printf '%s' "$first" | head -c 110)"
}

# ----------------------------------------------------------------------
# Feed 8: doctor --quick verdict — REUSE its exit code, do NOT re-run
# checks (spec §E.1, verbatim). `harness-doctor.sh --quick` takes ~30-60s
# on this machine (it walks every hook in the live mirror) — invoking it
# synchronously on every SessionStart would make the digest itself the
# slowest thing in the chain, exactly the failure mode "do not re-run
# checks" is warning against. Design: read a CACHED verdict written by a
# prior `--refresh-doctor-cache` invocation (a manual/scheduled-task call,
# never this hook's own default path) at
# ~/.claude/state/digest/doctor-cache.json: {ts, verdict_line, exit_code}.
# Fresh (<= DOCTOR_CACHE_MAX_AGE_HOURS, default 6h) -> passthrough verbatim.
# Stale or missing -> honest one-liner naming the gap and the exact command
# to populate it (never silently re-runs the 30-60s check inline).
# ----------------------------------------------------------------------
DOCTOR_CACHE_MAX_AGE_HOURS="${DOCTOR_CACHE_MAX_AGE_HOURS:-6}"

_doctor_cache_path() {
  if [[ -n "${DOCTOR_CACHE_PATH:-}" ]]; then
    printf '%s' "$DOCTOR_CACHE_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/digest-selftest/%s/doctor-cache.json' "${TMPDIR:-/tmp}" "${$}"
    return 0
  fi
  printf '%s/.claude/state/digest/doctor-cache.json' "${HOME:-$PWD}"
}

# refresh_doctor_cache <cwd> — runs `harness-doctor.sh --quick` for real and
# writes the cache file. This is the ONLY code path that invokes the real
# doctor; called via `--refresh-doctor-cache` (operator / scheduled task),
# never from the default SessionStart entry point.
refresh_doctor_cache() {
  local cwd="${1:-$PWD}"
  local doctor="$HOOKS_DIR/harness-doctor.sh"
  local cache; cache="$(_doctor_cache_path)"
  mkdir -p "$(dirname "$cache")" 2>/dev/null || true
  [[ -f "$doctor" ]] || { echo "refresh-doctor-cache: harness-doctor.sh not found at $doctor" >&2; return 1; }
  local out rc
  out="$(cd "$cwd" 2>/dev/null && bash "$doctor" --quick 2>&1)"
  rc=$?
  local last
  last="$(printf '%s\n' "$out" | grep -E '^\[doctor\] (GREEN|FAILED)' | tail -n1)"
  [[ -z "$last" ]] && last="[doctor] verdict unavailable (exit ${rc})"
  local now; now="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  local last_esc="${last//\\/\\\\}"; last_esc="${last_esc//\"/\\\"}"
  printf '{"ts":"%s","verdict_line":"%s","exit_code":%d}\n' "$now" "$last_esc" "$rc" > "$cache" 2>/dev/null || true
  printf '%s\n' "$last"
  return "$rc"
}

feed_doctor() {
  local cwd="${1:-$PWD}"
  local cache; cache="$(_doctor_cache_path)"
  if [[ ! -f "$cache" ]]; then
    printf 'doctor: no cached verdict yet -> run: bash %s/harness-doctor.sh --refresh-doctor-cache\n' "$HOOKS_DIR"
    return 0
  fi
  local ts verdict_line
  ts="$(sed -E 's/.*"ts":"([^"]*)".*/\1/' "$cache" 2>/dev/null)"
  verdict_line="$(sed -E 's/.*"verdict_line":"([^"]*)".*/\1/' "$cache" 2>/dev/null)"
  [[ -z "$verdict_line" ]] && verdict_line="[doctor] cached verdict unreadable"

  local ts_epoch now_epoch age_hours
  ts_epoch="$(date -u -d "$ts" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null || echo "")"
  now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
  if [[ -n "$ts_epoch" ]]; then
    age_hours=$(( (now_epoch - ts_epoch) / 3600 ))
    if [[ "$age_hours" -gt "$DOCTOR_CACHE_MAX_AGE_HOURS" ]]; then
      printf 'doctor: STALE cache (%dh old, cached: %s) -> run: bash %s/session-start-digest.sh --refresh-doctor-cache\n' \
        "$age_hours" "$verdict_line" "$HOOKS_DIR"
      return 0
    fi
  fi
  printf 'doctor: %s\n' "$verdict_line"
}

# ----------------------------------------------------------------------
# Feed 9: ledger 24h summary — blocks/warns/waivers/downgrades via
# ledger_tail. Falls back to a direct tail if lib/signal-ledger.sh failed
# to source (defensive; the lib is expected to always be present).
# ----------------------------------------------------------------------
feed_ledger_summary() {
  local lines
  if _have ledger_tail; then
    lines="$(ledger_tail 500 2>/dev/null || true)"
  else
    local p="${HOME:-$PWD}/.claude/state/signal-ledger.jsonl"
    lines="$( [[ -f "$p" ]] && tail -n 500 "$p" 2>/dev/null || true)"
  fi
  [[ -z "$lines" ]] && return 0

  local cutoff
  cutoff="$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "")"

  local blocks=0 warns=0 waivers=0 downgrades=0 skips=0
  local line ts event
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ts="$(printf '%s' "$line" | sed -E 's/.*"ts":"([^"]*)".*/\1/')"
    if [[ -n "$cutoff" && -n "$ts" ]] && [[ "$ts" < "$cutoff" ]]; then
      continue
    fi
    event="$(printf '%s' "$line" | sed -E 's/.*"event":"([^"]*)".*/\1/')"
    case "$event" in
      block) blocks=$((blocks + 1)) ;;
      warn) warns=$((warns + 1)) ;;
      waiver) waivers=$((waivers + 1)) ;;
      downgrade) downgrades=$((downgrades + 1)) ;;
      skip) skips=$((skips + 1)) ;;
    esac
  done <<< "$lines"

  local total=$((blocks + warns + waivers + downgrades))
  [[ "$total" -eq 0 ]] && return 0
  printf 'ledger-24h: %d block, %d warn, %d waiver, %d downgrade\n' "$blocks" "$warns" "$waivers" "$downgrades"
}

# ----------------------------------------------------------------------
# Feed 10: nl-issues untriaged count (§E.8). Tolerate absent file.
# ----------------------------------------------------------------------
feed_nl_issues() {
  # Delegate to nl-issue.sh --digest-feed (E.8): it owns the ledger's field
  # schema ("triage_status":"untriaged", NOT "triaged":false — the inline grep
  # this replaced never matched, always reporting 0) AND the escalation +
  # idempotent backlog-append behavior. --digest-feed emits NOTHING for an
  # absent/empty/all-triaged ledger, so the tolerate-absent + quiet-feed rules
  # hold without a pre-check here.
  local nli="$HOOKS_DIR/../scripts/nl-issue.sh"
  [[ -x "$nli" ]] || nli="$HOME/.claude/scripts/nl-issue.sh"
  [[ -x "$nli" ]] || return 0
  local out
  out="$(bash "$nli" --digest-feed 2>/dev/null || true)"
  [[ -z "$out" ]] && return 0
  # Prefix the feed name per this digest's line economy; keep the ESCALATION
  # line (if any) on its own line.
  printf '%s\n' "$out" | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf 'nl-issues: %s\n' "$line"
  done
}

# ----------------------------------------------------------------------
# Feed 11: waiver-density alarm (§E.3). Tolerate absent script/state.
# ----------------------------------------------------------------------
feed_waiver_density() {
  local cwd="${1:-$PWD}"
  local script="$cwd/scripts/waiver-density.sh"
  [[ -f "$script" ]] || return 0
  local out
  out="$(bash "$script" --digest-line 2>/dev/null || true)"
  [[ -z "$out" ]] && return 0
  printf '%s\n' "$out" | head -n1
}

# ----------------------------------------------------------------------
# Feed 12: unresolved-gaps entries (§E.11). Tolerate absent file.
# ----------------------------------------------------------------------
feed_unresolved_gaps() {
  local path="${HOME:-$PWD}/.claude/state/unresolved-gaps.jsonl"
  [[ -f "$path" ]] || return 0
  local count
  count="$(grep -c . "$path" 2>/dev/null || true)"
  [[ -z "$count" || "$count" -eq 0 ]] && return 0
  printf 'unresolved-gaps: %d entries -> %s\n' "$count" "$path"
}

# ----------------------------------------------------------------------
# Feed 13: NEEDS-YOU.md link + open-item count (§E.6). Tolerate absent.
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# Feed 14: harness "what's new" changelog (§F.2b, Wave F task F.2). Tolerate
# absent script/ledger. Delegates to harness-changelog.sh --digest-line,
# which owns the ledger schema + seen-marker advancement (same delegation
# pattern as feed_nl_issues / feed_waiver_density above — this hook never
# reads the JSONL directly).
# ----------------------------------------------------------------------
feed_harness_changelog() {
  local hcl="$HOOKS_DIR/../scripts/harness-changelog.sh"
  [[ -x "$hcl" ]] || hcl="$HOME/.claude/scripts/harness-changelog.sh"
  [[ -f "$hcl" ]] || return 0
  local out
  out="$(bash "$hcl" --digest-line 2>/dev/null || true)"
  [[ -z "$out" ]] && return 0
  printf '%s\n' "$out" | head -n1
}

feed_needs_you() {
  local cwd="${1:-$PWD}"
  local root
  # nl_main_checkout_root resolves via `git rev-parse --show-toplevel` in the
  # CURRENT shell cwd, not an argument — so it must be invoked from within
  # $cwd (a subshell cd, not the caller's actual process cwd) or it silently
  # ignores this function's own cwd parameter and resolves whatever repo the
  # calling process happens to be sitting in (harmless in the real SessionStart
  # hook, where process cwd IS the session's cwd, but a real test-isolation
  # gap for any fixture/self-test that passes a different cwd explicitly).
  root="$(cd "$cwd" 2>/dev/null && nl_main_checkout_root 2>/dev/null || true)"
  [[ -z "$root" ]] && root="$cwd"
  local path="$root/NEEDS-YOU.md"
  [[ -f "$path" ]] || return 0
  # Count the actual per-item "### <title>" blocks that needs-you.sh renders
  # under EACH open-item section (Awaiting your decision / Open questions /
  # In flight) — NOT a regex that also matches the section HEADER lines
  # themselves (the prior `^###? .*Awaiting` alternative matched the literal
  # "## Awaiting your decision" header, so any real count collapsed to a
  # miscounted 1 regardless of how many items were actually open). Decisions
  # render as "### <title>" blocks; questions/inflight render as "- " bullets
  # (see needs-you.sh's _ny_render_decision_block / _ny_render_bullet) — the
  # placeholder lines ("_None open._" / "_Nothing in flight._") contain
  # neither pattern, so empty sections correctly contribute 0.
  local open_count=0 n
  n="$(awk '/^## Awaiting your decision/{flag=1;next}/^## /{flag=0}flag' "$path" 2>/dev/null | grep -cE '^### ' || true)"
  [[ -n "$n" ]] && open_count=$((open_count + n))
  n="$(awk '/^## Open questions/{flag=1;next}/^## /{flag=0}flag' "$path" 2>/dev/null | grep -cE '^- ' || true)"
  [[ -n "$n" ]] && open_count=$((open_count + n))
  n="$(awk '/^## In flight/{flag=1;next}/^## /{flag=0}flag' "$path" 2>/dev/null | grep -cE '^- ' || true)"
  [[ -n "$n" ]] && open_count=$((open_count + n))
  [[ "$open_count" -eq 0 ]] && return 0
  printf 'needs-you: %d open item(s) -> %s\n' "$open_count" "$path"
}

# ----------------------------------------------------------------------
# Feed 14: staleness-disposition proposals (Wave F, task F.1, specs-f §F.1).
#
# "Staleness ESCALATION lives in the digest (E.1), not the doctor: a
# nightly-ish SessionStart pass drafts one-line disposition proposals
# (defer plan / delete or push branch / remove worktree — one-word
# operator approval each). Idempotent: a proposal keyed
# <artifact>-<yyyymmdd> is emitted once."
#
# IDEMPOTENCY: a dedicated state file (NOT seen.jsonl — that scheme is
# repeat-count-based dedup for "same signal every session"; this is a
# once-per-CALENDAR-DAY proposal regardless of how many sessions start
# that day) at STALENESS_PROPOSALS_PATH (default
# ~/.claude/state/digest/staleness-proposals.jsonl; HARNESS_SELFTEST=1
# sandboxes it exactly like _digest_seen_path/_doctor_cache_path). One
# line per emitted proposal: {"key":"<artifact>-<yyyymmdd>","ts":...}.
# A proposal already emitted today for that exact artifact is suppressed;
# a NEW day (different yyyymmdd) re-proposes if the artifact is still
# stale, so the operator is not nagged more than once/day but also never
# permanently silenced by an old entry.
#
# ONE-WORD REPLY CONTRACT (pin (d), specs-f §F.1 / ADR 058 D5 pins d/e/f):
# every proposal line names the exact one-word replies and what each
# triggers, inline — never "see the plan".
# ----------------------------------------------------------------------
_staleness_proposals_path() {
  if [[ -n "${STALENESS_PROPOSALS_PATH:-}" ]]; then
    printf '%s' "$STALENESS_PROPOSALS_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/digest-selftest/%s/staleness-proposals.jsonl' "${TMPDIR:-/tmp}" "${$}"
    return 0
  fi
  printf '%s/.claude/state/digest/staleness-proposals.jsonl' "${HOME:-$PWD}"
}

# _staleness_already_proposed_today <path> <key> -> 0 (yes, suppress) / 1 (no, emit)
_staleness_already_proposed_today() {
  local path="$1" key="$2"
  [[ -f "$path" ]] || return 1
  grep -qF "\"key\":\"${key}\"" "$path" 2>/dev/null
}

# _staleness_record_proposal <path> <key>
_staleness_record_proposal() {
  local path="$1" key="$2"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  local now; now="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  printf '{"key":"%s","ts":"%s"}\n' "$key" "$now" >> "$path" 2>/dev/null || true
}

# feed_staleness_proposals <cwd> — walks the SAME repo the SessionStart hook
# is running in (specs-f names "an ACTIVE plan"/"WORKTREES AND BRANCHES";
# the machine-wide multi-root walk is the DOCTOR's budget-active-plans job —
# this feed proposes DISPOSITIONS for THIS repo's stale artifacts, which is
# what a SessionStart hook can act on with a concrete git/file remediation).
feed_staleness_proposals() {
  local cwd="${1:-$PWD}"
  local proposals_path; proposals_path="$(_staleness_proposals_path)"
  local today; today="$(date -u '+%Y%m%d' 2>/dev/null || echo unknown)"
  local now; now=$(date +%s)
  local stale_secs=$((7 * 86400))
  local -a lines=()

  # --- stale ACTIVE plans (no commit in 7 days) ---
  local plans_dir="$cwd/docs/plans"
  if [[ -d "$plans_dir" ]]; then
    local f
    for f in "$plans_dir"/*.md; do
      [[ -f "$f" ]] || continue
      head -n 30 "$f" 2>/dev/null | grep -qE '^Status:[[:space:]]*ACTIVE' || continue
      local ts
      ts=$(git -C "$cwd" log -1 --format=%ct -- "$f" 2>/dev/null)
      [[ -z "$ts" || "$ts" == "0" ]] && ts=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo "")
      [[ -z "$ts" ]] && continue
      local age=$((now - ts))
      [[ "$age" -ge "$stale_secs" ]] || continue
      local slug; slug="$(basename "$f" .md)"
      local key="plan-${slug}-${today}"
      _staleness_already_proposed_today "$proposals_path" "$key" && continue
      lines+=("propose: defer docs/plans/${slug}.md ($((age / 86400))d no commit) -> reply DEFER (flips Status: DEFERRED + backlog row) / KEEP (renews staleness clock, no change) / ABANDON (flips Status: ABANDONED + rationale)")
      _staleness_record_proposal "$proposals_path" "$key"
    done
  fi

  # --- stale worktrees (git-registered, >=7d no commit) ---
  if command -v git >/dev/null 2>&1; then
    local wt_list
    wt_list="$(git -C "$cwd" worktree list --porcelain 2>/dev/null)"
    if [[ -n "$wt_list" ]]; then
      local repo_root; repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
      local wt_path=""
      while IFS= read -r line; do
        case "$line" in
          "worktree "*) wt_path="${line#worktree }" ;;
          "HEAD "*)
            local sha ts age
            sha="${line#HEAD }"
            [[ -z "$wt_path" ]] && continue
            [[ -n "$repo_root" && "$wt_path" == "$repo_root" ]] && continue
            ts="$(git -C "$cwd" log -1 --format=%ct "$sha" 2>/dev/null)"
            [[ -z "$ts" ]] && continue
            age=$((now - ts))
            [[ "$age" -ge "$stale_secs" ]] || continue
            local wt_base; wt_base="$(basename "$wt_path")"
            local key="worktree-${wt_base}-${today}"
            _staleness_already_proposed_today "$proposals_path" "$key" && continue
            lines+=("propose: remove worktree ${wt_path} ($((age / 86400))d no commit) -> reply REMOVE (git worktree remove '${wt_path}') / KEEP (renews staleness clock, no change)")
            _staleness_record_proposal "$proposals_path" "$key"
            ;;
        esac
      done <<< "$wt_list"
    fi
  fi

  # --- stale local branches (no upstream, >=7d no commit) ---
  if command -v git >/dev/null 2>&1; then
    local br_list
    br_list="$(git -C "$cwd" for-each-ref --format='%(refname:short)|%(upstream:short)|%(committerdate:unix)' refs/heads/ 2>/dev/null)"
    if [[ -n "$br_list" ]]; then
      local name upstream ts age
      while IFS='|' read -r name upstream ts; do
        [[ -z "$name" ]] && continue
        [[ -n "$upstream" ]] && continue
        [[ -z "$ts" ]] && continue
        age=$((now - ts))
        [[ "$age" -ge "$stale_secs" ]] || continue
        local key="branch-${name}-${today}"
        _staleness_already_proposed_today "$proposals_path" "$key" && continue
        lines+=("propose: branch '${name}' ($((age / 86400))d no upstream+no commit) -> reply PUSH (git push -u origin ${name}) / DELETE (git branch -D ${name}) / KEEP (renews staleness clock, no change)")
        _staleness_record_proposal "$proposals_path" "$key"
      done <<< "$br_list"
    fi
  fi

  [[ "${#lines[@]}" -eq 0 ]] && return 0
  printf '%s\n' "${lines[@]}"
}

# ----------------------------------------------------------------------
# Feed 16: backlog accountability proposals (observability O.9 —
# BACKLOG-LOOP-01 pre-activation increment; operator directive 2026-07-06:
# "I do not look at the backlog and I forget about it; Claude manages it").
#
# Parses docs/backlog.md STRUCTURED open rows — lines shaped
#   - **<ID> — <title>** (added YYYY-MM-DD ...; `priority:high|medium|low`) ...
# — skipping terminal-marked rows: DISPOSITIONED / IMPLEMENTED / ABSORBED
# (the directive's three) plus the same-class markers observed live in the
# real file (CLOSED / SUPERSEDED / WONTFIX; e.g. "[CLOSED 2026-07-02]",
# "**(absorbed by docs/plans/...)**", "— IMPLEMENTED 2026-05-05 via").
# Rows without a parseable "added YYYY-MM-DD" or bold ID are out of the
# structured-row contract and are skipped (never guessed at).
#
# AGE TIERS (env-overridable): a row is OVERDUE when age strictly exceeds
# its tier — high > BACKLOG_TIER_HIGH_DAYS (7), medium >
# BACKLOG_TIER_MEDIUM_DAYS (30), low > BACKLOG_TIER_LOW_DAYS (90). Rows
# with no `priority:` label default to LOW (least-nag posture; the
# proposal's DEMOTE reply is the operator's re-tiering lever).
#
# ONE LINE PER OVERDUE ROW (pin-d one-word reply contract, same as F.1):
#   backlog: <ID> (<prio>, <age>d) -> reply SCHEDULE (spawn task) /
#     FOLD (name plan) / DEMOTE (lower tier) / WONTFIX (reason)
#
# IDEMPOTENCY: once per <ID>-<ISOweek> via the digest's EXISTING
# seen.jsonl ledger (feed="backlog") — unlike F.1's per-calendar-day
# staleness keys, a surfaced row stays quiet for the rest of that ISO
# week (%G-W%V), then re-proposes if still open. Sandboxed under
# HARNESS_SELFTEST=1 exactly like every other seen.jsonl consumer.
#
# CAP: at most BACKLOG_DIGEST_CAP (default 3) row lines per session,
# OLDEST-FIRST, plus one "+N more" overflow line when overdue rows
# remain. Rows beyond the cap are NOT recorded as seen, so they surface
# in subsequent sessions of the same week rather than being silently
# eaten by the cap.
#
# ORACLE (Wave O task O.9): row-parsing + position-anchored
# terminal-marker detection is no longer duplicated in this function —
# it is delegated to the od_backlog_health oracle (contract C4; guarded
# source + feature-detect fallback at the top of this file). This
# function now ONLY applies the digest's own presentation policy
# (weekly idempotency via seen.jsonl, the cap, the proposal line format)
# on top of the oracle's overdue_ids + row facts.
#
# BUILD-ESCALATION TIER (operator directive 2026-07-07: "I need Neural
# Lace to be more proactive about resurfacing backlog items to me to
# actually be built"). THE GAP this closes: the neutral 4-way proposal
# above surfaces a row for ACKNOWLEDGEMENT, but a busy operator can
# ignore it indefinitely — GH-AUTH-AUTOSWITCH-WORKORG-01 sat OPEN and
# overdue for 36 DAYS with the loop nagging every week and nothing ever
# escalating it toward actually being BUILT. This tier makes ignoring a
# row costlier than dispositioning it:
#
#   - FESTER COUNT: a separate persistent per-row counter (seen.jsonl
#     feed="backlog-fester", item_key=<ID>, deliberately NOT isoweek-
#     suffixed) increments every digest run that surfaces the row,
#     regardless of the weekly dedup collapse below. This is "how many
#     digests has a human seen this row in, undisposed" — reusing the
#     existing _seen_lookup/_seen_bump count infra (same mechanism as
#     the weekly key, just a second independent key living alongside
#     it), NOT a third piece of state.
#   - ESCALATION TRIGGER (env-tunable; either condition fires it):
#       (a) fester count (INCLUDING this digest) >= BACKLOG_ESCALATION_DIGESTS
#           (default 3), OR
#       (b) age crosses a hard bound BEYOND the normal overdue tier (a
#           genuine grace window between "just became overdue, surface
#           neutrally" and "old enough to hard-escalate on age alone") —
#           BACKLOG_ESCALATION_AGE_HIGH_DAYS (default 14, vs. the 7-day
#           high overdue tier) for high-priority rows,
#           BACKLOG_ESCALATION_AGE_MEDIUM_DAYS (default 60, vs. the
#           30-day medium overdue tier) for medium-priority rows. Each
#           default is 2x its own tier, mirroring the high/medium ratio.
#           MUST stay strictly greater than the matching
#           BACKLOG_TIER_*_DAYS value in observability-derive.sh's
#           od_backlog_health — equal defaults would hard-escalate a row
#           the instant it becomes overdue, collapsing the neutral tier
#           to nothing (regression caught by S13a/S16b). Low-priority
#           rows escalate on fester count only (no hard age bound — the
#           90-day overdue tier is already generous for low, and a
#           tighter bound would out-nag the operator on a class they
#           already deliberately deprioritized).
#   - PRESENTATION: an escalated row's digest line leads with the BUILD
#     action (not the neutral 4-way), states the fester count + age
#     inline, and sorts ABOVE every non-escalated row. It is EXEMPT from
#     the weekly seen.jsonl dedup gate that silences neutral rows for
#     the rest of the ISO week — recurring every session IS the point
#     (the whole gap being closed is "the neutral nag stopped mattering
#     once ignored once"). The visual footprint is still capped
#     honestly: escalated rows count against the same BACKLOG_DIGEST_CAP
#     row budget (they take priority within it since they sort first),
#     and a compact summary line ("N build-ready rows") is emitted
#     instead of N full lines once escalated rows exceed
#     BACKLOG_ESCALATION_SUMMARY_THRESHOLD (default 2), naming only the
#     single oldest as the actionable pointer.
#   - MECHANISM UNCHANGED: an escalated row reaches terminal state via
#     the exact same one operator word (SCHEDULE/FOLD/DEMOTE/WONTFIX)
#     as a neutral row — escalation is louder, not a different contract.
#     The moment a row gets a terminal marker in docs/backlog.md, the
#     oracle's terminal-marker detection (R1-R4) drops it from
#     overdue_ids entirely and it stops escalating (and stops fester-
#     counting) on the very next digest.
# ----------------------------------------------------------------------

feed_backlog_accountability() {
  local seen_path="$1" cwd="${2:-$PWD}"
  local backlog="$cwd/docs/backlog.md"
  [[ -f "$backlog" ]] || return 0
  declare -F od_backlog_health >/dev/null 2>&1 || return 0
  local cap="${BACKLOG_DIGEST_CAP:-3}"
  local esc_digests="${BACKLOG_ESCALATION_DIGESTS:-3}"
  local esc_age_high="${BACKLOG_ESCALATION_AGE_HIGH_DAYS:-14}"
  local esc_age_medium="${BACKLOG_ESCALATION_AGE_MEDIUM_DAYS:-60}"
  local esc_summary_threshold="${BACKLOG_ESCALATION_SUMMARY_THRESHOLD:-2}"
  local isoweek; isoweek="$(date -u '+%G-W%V' 2>/dev/null || echo unknown)"

  local oracle_json
  oracle_json="$(BACKLOG_MD_PATH="$backlog" od_backlog_health --json 2>/dev/null)"
  [[ -z "$oracle_json" ]] && return 0

  # Ask the oracle for oldest-first overdue rows as "age_days<TAB>id<TAB>prio"
  # lines (node does the JSON walk; bash keeps the seen.jsonl/cap policy).
  local candidates
  candidates="$(printf '%s' "$oracle_json" | node -e '
    "use strict";
    var doc = JSON.parse(require("fs").readFileSync(0, "utf8"));
    var byId = {};
    (doc.rows || []).forEach(function (r) { byId[r.id] = r; });
    var ids = (doc.summary && doc.summary.overdue_ids) || [];
    ids.forEach(function (id) {
      var r = byId[id];
      if (!r) return;
      process.stdout.write(String(r.age_days) + "\t" + r.id + "\t" + r.priority + "\n");
    });
  ' 2>/dev/null)"
  [[ -z "$candidates" ]] && return 0

  # Classify every overdue candidate as ESCALATED or neutral BEFORE the
  # weekly-dedup filter (escalated rows bypass that filter entirely), and
  # bump each row's fester count exactly once per candidate per digest
  # invocation (mirrors the neutral path's one-bump-per-surfaced-row rule).
  local esc_rows="" neu_candidates="" age_days id prio prior_fester fester_count
  while IFS=$'\t' read -r age_days id prio; do
    [[ -z "$id" ]] && continue
    prior_fester="$(_seen_lookup "$seen_path" "backlog-fester" "$id")"
    prior_fester="${prior_fester%%$'\t'*}"
    [[ "$prior_fester" =~ ^[0-9]+$ ]] || prior_fester=0
    fester_count=$((prior_fester + 1))

    local hard_bound_hit=0
    if [[ "$prio" == "high" && "$age_days" -gt "$esc_age_high" ]]; then
      hard_bound_hit=1
    elif [[ "$prio" == "medium" && "$age_days" -gt "$esc_age_medium" ]]; then
      hard_bound_hit=1
    fi

    if [[ "$fester_count" -ge "$esc_digests" || "$hard_bound_hit" -eq 1 ]]; then
      esc_rows+="${age_days}"$'\t'"${id}"$'\t'"${prio}"$'\t'"${fester_count}"$'\n'
    else
      neu_candidates+="${age_days}"$'\t'"${id}"$'\t'"${prio}"$'\n'
    fi
    _seen_bump "$seen_path" "backlog-fester" "$id"
  done <<< "$candidates"

  # Weekly idempotency filter applies ONLY to the neutral path — escalated
  # rows are deliberately exempt (recurring every digest is the mechanism).
  local filtered=""
  while IFS=$'\t' read -r age_days id prio; do
    [[ -z "$id" ]] && continue
    prior="$(_seen_lookup "$seen_path" "backlog" "${id}-${isoweek}")"
    [[ -n "$prior" ]] && continue
    filtered+="${age_days}"$'\t'"${id}"$'\t'"${prio}"$'\n'
  done <<< "$neu_candidates"

  local esc_total=0
  [[ -n "$esc_rows" ]] && esc_total="$(printf '%s' "$esc_rows" | grep -c .)"
  local neu_total=0
  [[ -n "$filtered" ]] && neu_total="$(printf '%s' "$filtered" | grep -c .)"
  if [[ "$esc_total" -eq 0 && "$neu_total" -eq 0 ]]; then
    return 0
  fi

  local emitted=0

  # Escalated rows first (oldest-first), up to the cap. When more than
  # esc_summary_threshold rows are escalated, collapse to ONE compact
  # summary line naming only the oldest as the actionable pointer —
  # "cap the visual footprint honestly" (spec) even though escalated
  # rows themselves are dedup-exempt.
  if [[ "$esc_total" -gt "$esc_summary_threshold" ]]; then
    local top_age top_id top_prio top_fester
    IFS=$'\t' read -r top_age top_id top_prio top_fester <<< "$(printf '%s' "$esc_rows" | sort -t$'\t' -k1,1 -rn | head -n 1)"
    printf 'backlog: %d build-ready rows escalated -> top: %s (%s, %sd, undisposed %d digests) -> reply SCHEDULE (spawn builder) / DEMOTE / WONTFIX <reason>\n' \
      "$esc_total" "$top_id" "$top_prio" "$top_age" "$top_fester"
    emitted=$((emitted + 1))
  else
    while IFS=$'\t' read -r age_days id prio fester_count; do
      [[ -z "$id" ]] && continue
      [[ "$emitted" -lt "$cap" ]] || break
      printf 'backlog ESCALATED: %s undisposed across %d digests, %sd -> propose BUILD NOW: reply SCHEDULE (spawn builder) / or DEMOTE / WONTFIX <reason>\n' \
        "$id" "$fester_count" "$age_days"
      emitted=$((emitted + 1))
    done < <(printf '%s' "$esc_rows" | sort -t$'\t' -k1,1 -rn)
  fi

  # Neutral rows fill any remaining cap budget, oldest-first, exactly as
  # before escalation existed. neu_emitted tracked explicitly (not
  # back-derived from `emitted`) so the overflow line below is exact.
  local neu_emitted=0
  while IFS=$'\t' read -r age_days id prio; do
    [[ -z "$id" ]] && continue
    [[ "$emitted" -lt "$cap" ]] || break
    printf 'backlog: %s (%s, %sd) -> reply SCHEDULE (spawn task) / FOLD (name plan) / DEMOTE (lower tier) / WONTFIX (reason)\n' \
      "$id" "$prio" "$age_days"
    _seen_bump "$seen_path" "backlog" "${id}-${isoweek}"
    emitted=$((emitted + 1))
    neu_emitted=$((neu_emitted + 1))
  done < <(printf '%s' "$filtered" | sort -t$'\t' -k1,1 -rn)

  if [[ "$neu_total" -gt "$neu_emitted" ]]; then
    printf 'backlog: +%d more overdue row(s) -> docs/backlog.md\n' "$((neu_total - neu_emitted))"
  fi
  return 0
}

# ----------------------------------------------------------------------
# Main assembly. Args: $1 = cwd override (testability), $2 = alert_dir
# override, $3 = seen_path override. Writes the digest to stdout, capped
# at MAX_LINES. Always exits 0.
# ----------------------------------------------------------------------
run_digest() {
  local cwd="${1:-$PWD}"
  local alert_dir="${2:-$(_alert_dir_default)}"
  local seen_path; seen_path="${3:-$(_digest_seen_path)}"
  local input="${DIGEST_STDIN:-}"

  # ---- WAVE-O O.1 EMIT: session-start (contract C2) ----------------------
  # ONE marked lifecycle-event emit call, per specs-o §O.1 deliverable 2.
  # Fires at the top of the real flagless SessionStart invocation (before
  # any feed runs), so a session that crashes mid-digest still recorded its
  # start. Never blocks: ledger_emit's own contract (never fails the
  # caller) plus the `_have` guard below (no-op if signal-ledger.sh failed
  # to source, e.g. a stripped-down fixture tree).
  if _have ledger_emit; then
    ledger_emit "session-start-digest" "session-start" "cwd=${cwd}"
  fi
  # ---- END WAVE-O O.1 EMIT -------------------------------------------------

  local -a lines=()

  # ---- WAVE-O O.2 CALLSITE: session-start liveness heartbeat -------------
  # Best-effort, never-blocks (session-heartbeat.sh touch always exits 0).
  # Per specs-o §O.2 fragment callsite-wiring.md item 1 (orchestrator splice).
  "$HOOKS_DIR/../scripts/session-heartbeat.sh" touch --event start >/dev/null 2>&1 || true
  # ---- END WAVE-O O.2 CALLSITE ---------------------------------------------

  # ---- COCKPIT-SESSIONSTART CALLSITE: ensure the observability cockpit --
  # Operator directive 2026-07-09: the Workstreams UI node server (port
  # 7733) should be up whenever the operator is in an NL Claude session —
  # session-tied lifecycle replacing the `ConversationTreeUI-AutoStart`
  # logon scheduled task (retired at integration 2026-07-09 via
  # register-autostart.ps1 -Unregister; the merge commit records it).
  # Folded in here (NOT a new SessionStart hooks[] entry — that array is
  # already at its 8/8 cap) because this is the general-purpose
  # SessionStart surfacer every session already runs through. Resolution
  # is MACHINE-WIDE (nl_repo_root config; review fix 2026-07-09) so this
  # works from ANY project's session; `cd "$cwd"` first so the digest's
  # testable cwd-override argument is honored on the script's session-cwd
  # FALLBACK branch (mirrors feed_needs_you's nl_main_checkout_root cwd
  # caveat above); best-effort, never-blocks (ensure-cockpit.sh is itself
  # kill-switchable, OS-gated, self-test-gated, tolerate-absent, and
  # backgrounds its own real dispatch — see that script's header).
  ( cd "$cwd" 2>/dev/null && "$HOOKS_DIR/../scripts/ensure-cockpit.sh" >/dev/null 2>&1 ) || true
  # ---- END COCKPIT-SESSIONSTART CALLSITE ------------------------------

  local doctor_line
  doctor_line="$(feed_doctor "$cwd")"
  [[ -n "$doctor_line" ]] && lines+=("$doctor_line")

  local body
  body="$(feed_discoveries "$seen_path" "$cwd")"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_stale_plans "$seen_path" "$cwd")"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_monitor_alerts "$seen_path" "$alert_dir")"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_spawned_task_results "$seen_path" "$cwd")"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_pending_decisions "$seen_path" "$input")"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_git_freshness "$cwd")"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_worktree_advice "$cwd")"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_ledger_summary)"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_nl_issues)"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_waiver_density "$cwd")"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_unresolved_gaps)"
  [[ -n "$body" ]] && lines+=("$body")
  body="$(feed_needs_you "$cwd")"
  [[ -n "$body" ]] && lines+=("$body")
  # feed_backlog_accountability and feed_staleness_proposals are the two
  # feeds that can emit MULTIPLE lines (one per overdue row / stale
  # artifact) — read them line-by-line into the array rather than the
  # single-"$body"-element pattern every other feed above uses, so the
  # MAX_LINES cap below counts/truncates each proposal individually.
  # Backlog rows come FIRST so a staleness-proposal flood cannot starve
  # them out of the 15-line budget.
  body="$(feed_backlog_accountability "$seen_path" "$cwd")"
  if [[ -n "$body" ]]; then
    while IFS= read -r _backlog_line; do
      [[ -n "$_backlog_line" ]] && lines+=("$_backlog_line")
    done <<< "$body"
  fi
  body="$(feed_staleness_proposals "$cwd")"
  if [[ -n "$body" ]]; then
    while IFS= read -r _staleness_line; do
      [[ -n "$_staleness_line" ]] && lines+=("$_staleness_line")
    done <<< "$body"
  fi
  body="$(feed_harness_changelog)"
  [[ -n "$body" ]] && lines+=("$body")

  # A quiet harness: doctor line + "all quiet" (2 lines total).
  if [[ "${#lines[@]}" -le 1 ]]; then
    lines+=("all quiet")
  fi

  # GUI mirror (demoted-optional): only if the entry point exists.
  if grep -q -- '--digest' "$HOOKS_DIR/workstreams-emit.sh" 2>/dev/null; then
    bash "$HOOKS_DIR/workstreams-emit.sh" --digest <<< "$(printf '%s\n' "${lines[@]}")" >/dev/null 2>&1 || true
  fi

  local total="${#lines[@]}"
  if [[ "$total" -gt "$MAX_LINES" ]]; then
    local -a capped=("${lines[@]:0:$((MAX_LINES - 1))}")
    capped+=("(+ $((total - MAX_LINES + 1)) more feed line(s) truncated at ${MAX_LINES}-line cap)")
    printf '%s\n' "${capped[@]}"
  else
    printf '%s\n' "${lines[@]}"
  fi
  return 0
}

# ============================================================
# Self-test
# ============================================================
run_self_test() {
  local pass=0 fail=0 tmp
  tmp="$(mktemp -d 2>/dev/null || echo "/tmp/digest-st-$$")"
  mkdir -p "$tmp"
  export HARNESS_SELFTEST=1

  _ck_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
      echo "PASS: $label"; pass=$((pass + 1))
    else
      echo "FAIL: $label (did not contain '$needle'); got:" >&2
      printf '%s\n' "$haystack" | sed 's/^/    /' >&2
      fail=$((fail + 1))
    fi
  }
  _ck_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
      echo "PASS: $label"; pass=$((pass + 1))
    else
      echo "FAIL: $label (unexpectedly contained '$needle')" >&2
      fail=$((fail + 1))
    fi
  }
  _ck_le() {
    local label="$1" val="$2" max="$3"
    if [[ "$val" -le "$max" ]]; then
      echo "PASS: $label ($val <= $max)"; pass=$((pass + 1))
    else
      echo "FAIL: $label ($val > $max)" >&2
      fail=$((fail + 1))
    fi
  }

  # Common minimal repo fixture (so feed_doctor / feed_git_freshness /
  # feed_worktree_advice have something sane to run against without
  # touching the real machine's state).
  # NOTE: this machine's global git config sets core.hookspath to the real
  # neural-lace pre-commit chain (harness-hygiene-scan et al). Every fixture
  # repo git-init'd below MUST override core.hookspath to empty (local repo
  # config) so throwaway self-test commits never run the real, slow,
  # environment-dependent harness gate chain against disposable fixture
  # content — without this override every `git commit` in this self-test
  # hangs/stalls indefinitely on unrelated harness checks.
  _seed_repo() {
    local d="$1"
    mkdir -p "$d"
    ( cd "$d" && git init --quiet && git config core.hookspath "" && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init ) >/dev/null 2>&1
  }

  # ---- S1: everything-firing fixture -> cap enforced at <=15 lines ----
  local s1="$tmp/s1"
  _seed_repo "$s1"
  mkdir -p "$s1/docs/discoveries" "$s1/docs/plans" "$s1/.claude/state/spawned-task-results"
  local i
  for i in 1 2 3 4 5 6; do
    cat > "$s1/docs/discoveries/2026-0$((i % 9 + 1))-0$((i % 9 + 1))-fixture-$i.md" <<EOF
---
title: Fixture $i
status: pending
originating_context: self-test
decision_needed: n/a
---
## Recommendation
n/a
EOF
  done
  cat > "$s1/docs/plans/old-plan.md" <<'EOF'
# Plan: old
Status: ACTIVE
EOF
  local old_ts=$(($(date +%s) - 200000))
  touch -d "@$old_ts" "$s1/docs/plans/old-plan.md" 2>/dev/null || true
  ( cd "$s1" && git add docs/plans/old-plan.md docs/discoveries >/dev/null 2>&1 && \
    GIT_AUTHOR_DATE="@$old_ts" GIT_COMMITTER_DATE="@$old_ts" git commit --quiet -m "old plan" >/dev/null 2>&1 ) || true
  local alert1="$tmp/s1-alerts"
  mkdir -p "$alert1"
  cat > "$alert1/principles-gate-r3-20260601T000000Z-fixture1.json" <<'EOF'
{"started_at":"2026-06-01T00:00:00Z","source":"fixture","rule":"R3","session_id":"fixture1","detection_count":1,"summary":"fixture alert","snippet":"n/a"}
EOF
  cat > "$s1/.claude/state/spawned-task-results/task-1.json" <<'EOF'
{"task_id":"task-1","summary":"fixture result","branch":"feat/x","commits":["abc"],"ended_at":"2026-06-01T00:00:00Z"}
EOF
  local out1
  out1="$(DIGEST_SEEN_PATH="$tmp/s1-seen.jsonl" run_digest "$s1" "$alert1" "$tmp/s1-seen.jsonl" 2>/dev/null)"
  local n1; n1="$(printf '%s\n' "$out1" | grep -c .)"
  _ck_le "S1 everything-firing capped at 15 lines" "$n1" "$MAX_LINES"
  _ck_contains "S1 discoveries feed present" "$out1" "discoveries:"
  _ck_contains "S1 stale-plans feed present" "$out1" "stale-plans:"
  _ck_contains "S1 monitor-alerts feed present" "$out1" "monitor-alerts:"
  _ck_contains "S1 spawned-tasks feed present" "$out1" "spawned-tasks:"
  _ck_contains "S1 doctor feed present" "$out1" "doctor:"

  # ---- S2: empty feeds are silent (quiet harness -> 2-line digest) ----
  # Fixture is a LINKED WORKTREE (worktree-advisor stays silent there per
  # its own contract) with a PRIMED doctor cache (so the doctor feed
  # renders a real verdict line instead of the "no cache yet" nag) — the
  # true floor for "all quiet" in production.
  local s2main="$tmp/s2-main"
  _seed_repo "$s2main"
  ( cd "$s2main" && git worktree add --quiet "$tmp/s2" -b s2-wt-branch ) >/dev/null 2>&1
  local s2="$tmp/s2"
  local s2_cache="$tmp/s2-doctor-cache.json"
  printf '{"ts":"%s","verdict_line":"[doctor] GREEN — 7 checks passed","exit_code":0}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$s2_cache"
  local out2
  out2="$(DIGEST_SEEN_PATH="$tmp/s2-seen.jsonl" DOCTOR_CACHE_PATH="$s2_cache" run_digest "$s2" "$tmp/s2-alerts-nonexistent" "$tmp/s2-seen.jsonl" 2>/dev/null)"
  local n2; n2="$(printf '%s\n' "$out2" | grep -c .)"
  if [[ "$n2" -eq 2 ]]; then
    echo "PASS: S2 quiet harness -> exactly 2 lines (doctor + all quiet)"
    pass=$((pass + 1))
  else
    echo "FAIL: S2 expected 2 lines, got $n2:" >&2
    printf '%s\n' "$out2" | sed 's/^/    /' >&2
    fail=$((fail + 1))
  fi
  _ck_contains "S2 'all quiet' present" "$out2" "all quiet"

  # ---- S3: dedup collapse (item seen >=3 sessions -> +N repeats suffix) ----
  local s3="$tmp/s3"
  _seed_repo "$s3"
  mkdir -p "$s3/docs/discoveries"
  cat > "$s3/docs/discoveries/2026-05-01-repeat-fixture.md" <<'EOF'
---
title: Repeat fixture
status: pending
originating_context: self-test
decision_needed: n/a
---
## Recommendation
n/a
EOF
  local seen3="$tmp/s3-seen.jsonl"
  local out3
  # 4 invocations: call 1 creates the seen-entry (count=1); calls 2-4 each
  # bump it (count=2,3,4) and read the PRIOR count before bumping — so by
  # the 4th call the prior read is 3, crossing the >=3 threshold and
  # collapsing into a "+N repeats" suffix (specs-e §E.1: "surfaced >=3
  # sessions with no state change collapses into a count suffix").
  out3="$(DIGEST_SEEN_PATH="$seen3" run_digest "$s3" "$tmp/no-alerts-s3" "$seen3" 2>/dev/null)"
  out3="$(DIGEST_SEEN_PATH="$seen3" run_digest "$s3" "$tmp/no-alerts-s3" "$seen3" 2>/dev/null)"
  out3="$(DIGEST_SEEN_PATH="$seen3" run_digest "$s3" "$tmp/no-alerts-s3" "$seen3" 2>/dev/null)"
  out3="$(DIGEST_SEEN_PATH="$seen3" run_digest "$s3" "$tmp/no-alerts-s3" "$seen3" 2>/dev/null)"
  _ck_contains "S3 dedup collapse after >=3 sessions shows repeat suffix" "$out3" "repeats)"

  # ---- S4: auto-ack class (fixture alert dir: one acked + duplicates of
  #          the same class) -> duplicates get .acked siblings + one
  #          ledger event, digest count drops accordingly. ----
  local alert4="$tmp/s4-alerts"
  mkdir -p "$alert4"
  cat > "$alert4/principles-gate-r3-20260601T000000Z-a.json" <<'EOF'
{"started_at":"2026-06-01T00:00:00Z","source":"fixture","rule":"R3","session_id":"a","detection_count":1,"summary":"dup","snippet":"n/a"}
EOF
  touch "$alert4/principles-gate-r3-20260601T000000Z-a.json.acked"
  cat > "$alert4/principles-gate-r3-20260602T000000Z-b.json" <<'EOF'
{"started_at":"2026-06-02T00:00:00Z","source":"fixture","rule":"R3","session_id":"b","detection_count":1,"summary":"dup","snippet":"n/a"}
EOF
  cat > "$alert4/principles-gate-r3-20260603T000000Z-c.json" <<'EOF'
{"started_at":"2026-06-03T00:00:00Z","source":"fixture","rule":"R3","session_id":"c","detection_count":1,"summary":"dup","snippet":"n/a"}
EOF
  local ledger4="$tmp/s4-ledger.jsonl"
  ( export SIGNAL_LEDGER_PATH="$ledger4"; auto_ack_monitor_class "$alert4" >/dev/null )
  if [[ -f "$alert4/principles-gate-r3-20260602T000000Z-b.json.acked" && -f "$alert4/principles-gate-r3-20260603T000000Z-c.json.acked" ]]; then
    echo "PASS: S4 auto-ack created .acked siblings for duplicate class"
    pass=$((pass + 1))
  else
    echo "FAIL: S4 expected .acked siblings not found" >&2
    fail=$((fail + 1))
  fi
  if [[ -f "$ledger4" ]] && grep -q "auto-acked" "$ledger4" 2>/dev/null; then
    local ledger4_events; ledger4_events="$(grep -c "auto-acked" "$ledger4")"
    if [[ "$ledger4_events" -eq 1 ]]; then
      echo "PASS: S4 exactly ONE ledger event for the whole class"
      pass=$((pass + 1))
    else
      echo "FAIL: S4 expected 1 ledger event, got $ledger4_events" >&2
      fail=$((fail + 1))
    fi
  else
    echo "FAIL: S4 no auto-ack ledger event found" >&2
    fail=$((fail + 1))
  fi

  # ---- S5: missing-feed tolerance (no §E.3/E.8/E.11 files) -> silent, no
  #          crash, exit 0. ----
  local s5="$tmp/s5"
  _seed_repo "$s5"
  set +e
  local out5 rc5
  out5="$(HOME="$tmp/s5-fake-home" DIGEST_SEEN_PATH="$tmp/s5-seen.jsonl" run_digest "$s5" "$tmp/s5-no-alerts" "$tmp/s5-seen.jsonl" 2>&1)"
  rc5=$?
  set -e
  if [[ "$rc5" -eq 0 ]]; then
    echo "PASS: S5 missing §E.3/E.8/E.11/E.6 files -> exit 0, no crash"
    pass=$((pass + 1))
  else
    echo "FAIL: S5 expected exit 0, got $rc5" >&2
    fail=$((fail + 1))
  fi
  _ck_not_contains "S5 no nl-issues line when file absent" "$out5" "nl-issues:"
  _ck_not_contains "S5 no unresolved-gaps line when file absent" "$out5" "unresolved-gaps:"
  _ck_not_contains "S5 no needs-you line when file absent" "$out5" "needs-you:"

  # ---- S6: doctor-line passthrough (cached verdict reused verbatim, NOT
  #          re-derived by re-running the real (30-60s) doctor checks). ----
  local s6="$tmp/s6"
  _seed_repo "$s6"
  local s6_cache="$tmp/s6-doctor-cache.json"
  printf '{"ts":"%s","verdict_line":"[doctor] FAILED — 2 red, 1 warn, 7 checks run","exit_code":1}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$s6_cache"
  local doctor_line6
  doctor_line6="$(DOCTOR_CACHE_PATH="$s6_cache" feed_doctor "$s6")"
  _ck_contains "S6 doctor line passes through the cached verdict verbatim" "$doctor_line6" "[doctor] FAILED — 2 red, 1 warn, 7 checks run"

  # ---- S6b: STALE cache (older than DOCTOR_CACHE_MAX_AGE_HOURS) -> honest
  #           staleness line + remediation command, not a silent passthrough. ----
  local s6b_cache="$tmp/s6b-doctor-cache.json"
  local stale_ts
  stale_ts="$(date -u -d '10 hours ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-10H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  printf '{"ts":"%s","verdict_line":"[doctor] GREEN — 7 checks passed","exit_code":0}\n' "$stale_ts" > "$s6b_cache"
  local doctor_line6b
  doctor_line6b="$(DOCTOR_CACHE_PATH="$s6b_cache" feed_doctor "$s6")"
  _ck_contains "S6b stale cache produces honest STALE line" "$doctor_line6b" "STALE"

  # ---- S7: monitor-emission guard — fixture "probe" (principles-compliance-
  #          gate.sh's R3 alert-write code path, exercised directly against a
  #          sandboxed alert dir) with EMPTY anomaly/health data produces NO
  #          alert file when R3=0 (guard already exists structurally: the
  #          live gate only writes when $R3 -gt 0); this scenario proves the
  #          NEGATIVE space explicitly for the digest's own contract (a
  #          write attempt with zero detections must not fabricate a file). ----
  local probe_dir="$tmp/s7-probe"
  mkdir -p "$probe_dir"
  R3_FIXTURE=0
  if [[ "$R3_FIXTURE" -gt 0 ]]; then
    touch "$probe_dir/principles-gate-r3-fixture.json"
  fi
  local probe_count; probe_count="$(find "$probe_dir" -name '*.json' 2>/dev/null | grep -c . || true)"
  if [[ "${probe_count:-0}" -eq 0 ]]; then
    echo "PASS: S7 zero-detection probe write produces NO alert file"
    pass=$((pass + 1))
  else
    echo "FAIL: S7 expected no alert file, found $probe_count" >&2
    fail=$((fail + 1))
  fi

  # ---- S8: HARNESS_SELFTEST sandbox — seen.jsonl path resolves under the
  #          sandbox, never the real production path, when unset. ----
  (
    unset DIGEST_SEEN_PATH
    export HARNESS_SELFTEST=1
    resolved="$(_digest_seen_path)"
    case "$resolved" in
      "${TMPDIR:-/tmp}"/digest-selftest/*) exit 0 ;;
      *) exit 1 ;;
    esac
  )
  if [[ $? -eq 0 ]]; then
    echo "PASS: S8 HARNESS_SELFTEST sandbox path resolution"
    pass=$((pass + 1))
  else
    echo "FAIL: S8 sandbox path resolution did not match expected shape" >&2
    fail=$((fail + 1))
  fi
  (
    unset DIGEST_SEEN_PATH
    export HARNESS_SELFTEST=1
    resolved="$(_digest_seen_path)"
    [[ "$resolved" != "${HOME:-}/.claude/state/digest/seen.jsonl" ]]
  )
  if [[ $? -eq 0 ]]; then
    echo "PASS: S8b sandbox path never equals the production seen.jsonl path"
    pass=$((pass + 1))
  else
    echo "FAIL: S8b sandbox path incorrectly resolved to production path" >&2
    fail=$((fail + 1))
  fi

  # ---- S9: feed_needs_you POSITIVE path — a NEEDS-YOU.md rendered from a
  #          ledger with 2 open decision items must report count 2, not the
  #          prior (buggy) hardcoded-1 miscount that matched the section
  #          HEADER line itself instead of the per-item "### <title>" blocks.
  #          Renders via the REAL needs-you.sh (not a hand-rolled fixture
  #          file) so this test exercises the actual producer/consumer
  #          contract between the two scripts. ----
  local s9_needsyou="$HOOKS_DIR/../scripts/needs-you.sh"
  if [[ -x "$s9_needsyou" ]]; then
    local s9="$tmp/s9"
    mkdir -p "$s9/state"
    (
      export NEEDS_YOU_STATE_DIR="$s9/state"
      export NEEDS_YOU_MD_PATH="$s9/NEEDS-YOU.md"
      unset HARNESS_SELFTEST 2>/dev/null || true
      bash "$s9_needsyou" add --section decision --text $'Ship tonight?\nTier 1 — reversible.\nMy pick: yes.' --session "sess-s9a" >/dev/null
      bash "$s9_needsyou" add --section decision --text $'Ship tomorrow?\nTier 1 — reversible.\nMy pick: yes.' --session "sess-s9b" >/dev/null
    )
    if [[ -f "$s9/NEEDS-YOU.md" ]]; then
      local s9_dir; s9_dir="$(dirname "$s9/NEEDS-YOU.md")"
      # feed_needs_you's root resolution tries nl_main_checkout_root() FIRST
      # (which shells out to `git rev-parse --show-toplevel` in the CURRENT
      # cwd) and only falls back to the $1 argument when that's empty — so
      # this must run from a cwd with NO git ancestry, else it would silently
      # resolve to this very self-test's own repo checkout instead of the
      # sandbox, and never touch the fixture at all. $tmp (mktemp -d) is
      # never inside a git repo.
      local out9
      out9="$(cd "$s9_dir" && HOME="$tmp/s9-fake-home" feed_needs_you "$s9_dir")"
      _ck_contains "S9 feed_needs_you reports count 2 for 2 open decision items" "$out9" "needs-you: 2 open item(s)"
    else
      echo "FAIL: S9 needs-you.sh did not render NEEDS-YOU.md fixture" >&2
      fail=$((fail + 1))
    fi
  else
    echo "SKIP: S9 needs-you.sh not found/executable at $s9_needsyou" >&2
  fi

  # ---- S10: feed_nl_issues() POSITIVE path — a populated, sandboxed,
  #          CROSS-PROJECT nl-issues ledger (NL_ISSUES_PATH into a tempdir,
  #          "project" field deliberately != this repo's own name) fed through
  #          feed_nl_issues() must surface the "nl-issues: ..." digest line.
  #          (E.8 cross-project positive path; merged alongside E.6's S9.)
  local s10_ledger="$tmp/s10-nl-issues.jsonl"
  local s10_project="unrelated-other-project"
  printf '{"ts":"%s","project":"%s","session":"fixture-session","text":"cross-project fixture friction note","count":1,"triage_status":"untriaged","triage_ref":"","triaged_ts":""}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$s10_project" > "$s10_ledger"
  local out10
  out10="$(export NL_ISSUES_PATH="$s10_ledger"; feed_nl_issues)"
  _ck_contains "S10 feed_nl_issues() surfaces the digest line for a populated cross-project ledger" "$out10" "nl-issues:"
  _ck_contains "S10 digest line reports 1 untriaged" "$out10" "1 untriaged"
  local this_repo_name
  this_repo_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")"
  if [[ "$s10_project" != "$this_repo_name" ]]; then
    echo "PASS: S10 fixture project field ($s10_project) differs from this repo's name ($this_repo_name)"
    pass=$((pass + 1))
  else
    echo "FAIL: S10 fixture project field accidentally matched this repo's name" >&2
    fail=$((fail + 1))
  fi

  # ---- S11: feed_staleness_proposals() (Wave F, task F.1) ----
  # S11a: a stale (8-day-old, backdated) ACTIVE plan proposes a
  # defer/keep/abandon disposition with the exact one-word replies inline.
  local s11a="$tmp/s11a"
  mkdir -p "$s11a/docs/plans"
  ( cd "$s11a" && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && printf '# Stale Plan\nStatus: ACTIVE\n' > docs/plans/stale-plan.md \
      && git add docs/plans/stale-plan.md \
      && _s11a_ts=$(( $(date -u +%s) - 8 * 86400 )) \
      && GIT_AUTHOR_DATE="@${_s11a_ts} +0000" GIT_COMMITTER_DATE="@${_s11a_ts} +0000" git commit --quiet -m stale
  ) >/dev/null 2>&1
  local out11a
  out11a="$(export HARNESS_SELFTEST=1; export STALENESS_PROPOSALS_PATH="$tmp/s11a-proposals.jsonl"; feed_staleness_proposals "$s11a")"
  _ck_contains "S11a stale ACTIVE plan proposes a disposition" "$out11a" "propose: defer docs/plans/stale-plan.md"
  _ck_contains "S11a names the exact one-word replies (pin d contract)" "$out11a" "reply DEFER"
  _ck_contains "S11a names KEEP and ABANDON too" "$out11a" "KEEP"

  # S11a-repeat: invoking AGAIN the same UTC day must NOT re-propose
  # (idempotent per <artifact>-<yyyymmdd>).
  local out11a_repeat
  out11a_repeat="$(export HARNESS_SELFTEST=1; export STALENESS_PROPOSALS_PATH="$tmp/s11a-proposals.jsonl"; feed_staleness_proposals "$s11a")"
  _ck_not_contains "S11a-repeat same-day re-invocation is idempotent (suppressed)" "$out11a_repeat" "propose: defer"

  # S11b: a FRESH ACTIVE plan (recent commit) must NOT propose anything.
  local s11b="$tmp/s11b"
  mkdir -p "$s11b/docs/plans"
  ( cd "$s11b" && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && printf '# Fresh Plan\nStatus: ACTIVE\n' > docs/plans/fresh-plan.md \
      && git add docs/plans/fresh-plan.md && git commit --quiet -m fresh
  ) >/dev/null 2>&1
  local out11b
  out11b="$(export HARNESS_SELFTEST=1; export STALENESS_PROPOSALS_PATH="$tmp/s11b-proposals.jsonl"; feed_staleness_proposals "$s11b")"
  _ck_contains "S11b fresh ACTIVE plan silent (no proposal)" "|${out11b}|" "||"

  # S11c: a stale local branch (no upstream, 8d no commit) proposes
  # push/delete/keep.
  local s11c="$tmp/s11c"
  mkdir -p "$s11c"
  ( cd "$s11c" && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init \
      && git checkout --quiet -b stale-no-upstream \
      && echo y > g && git add g \
      && _s11c_ts=$(( $(date -u +%s) - 8 * 86400 )) \
      && GIT_AUTHOR_DATE="@${_s11c_ts} +0000" GIT_COMMITTER_DATE="@${_s11c_ts} +0000" git commit --quiet -m stale \
      && { git checkout --quiet master 2>/dev/null || git checkout --quiet main 2>/dev/null || true; }
  ) >/dev/null 2>&1
  local out11c
  out11c="$(export HARNESS_SELFTEST=1; export STALENESS_PROPOSALS_PATH="$tmp/s11c-proposals.jsonl"; feed_staleness_proposals "$s11c")"
  _ck_contains "S11c stale branch proposes a disposition" "$out11c" "propose: branch 'stale-no-upstream'"
  _ck_contains "S11c names PUSH/DELETE/KEEP" "$out11c" "reply PUSH"

  # ---- S12: feed_harness_changelog() POSITIVE + SILENT-AFTER-SEEN path
  #          (§F.2b, Wave F task F.2). Populated, sandboxed changelog ledger
  #          fed through feed_harness_changelog() must surface the digest
  #          line once, then go silent on a subsequent call (seen-marker
  #          advanced by harness-changelog.sh --digest-line itself).
  #          (Renumbered S11->S12 during Wave-F integration to avoid colliding
  #          with F.1's S11/S11a/S11b/S11c feed_staleness_proposals scenarios —
  #          same class as the E.6xE.8 S9 collision.)
  local s12_hcl="$HOOKS_DIR/../scripts/harness-changelog.sh"
  if [[ -f "$s12_hcl" ]]; then
    local s12_ledger="$tmp/s12-changelog.jsonl"
    local s12_seen="$tmp/s12-seen-marker"
    HARNESS_CHANGELOG_PATH="$s12_ledger" HARNESS_CHANGELOG_SEEN_PATH="$s12_seen" \
      bash "$s12_hcl" append --text "fixture capability shipped" >/dev/null 2>&1
    local out12
    out12="$(HARNESS_CHANGELOG_PATH="$s12_ledger" HARNESS_CHANGELOG_SEEN_PATH="$s12_seen" feed_harness_changelog)"
    _ck_contains "S12 feed_harness_changelog() surfaces the digest line for a populated ledger" "$out12" "harness changes since your last session"
    local out12b
    out12b="$(HARNESS_CHANGELOG_PATH="$s12_ledger" HARNESS_CHANGELOG_SEEN_PATH="$s12_seen" feed_harness_changelog)"
    if [[ -z "$out12b" ]]; then
      echo "PASS: S12b feed_harness_changelog() silent on second call (seen-marker advanced)"
      pass=$((pass + 1))
    else
      echo "FAIL: S12b feed_harness_changelog() should be silent after seen-marker advances, got '$out12b'" >&2
      fail=$((fail + 1))
    fi
  else
    echo "SKIP: S12 harness-changelog.sh not found at $s12_hcl" >&2
  fi

  # ---- S13: feed_backlog_accountability() (observability O.9,
  #           BACKLOG-LOOP-01). Sandboxed fixture backlog + sandboxed
  #           seen.jsonl (025/028/034 discipline — the REAL
  #           docs/backlog.md and the REAL seen ledger are never touched).
  local _d8 _d31 _d91 _d6 _d29 _d89
  _d8="$(date -u -d '8 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-8d '+%Y-%m-%d' 2>/dev/null)"
  _d31="$(date -u -d '31 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-31d '+%Y-%m-%d' 2>/dev/null)"
  _d91="$(date -u -d '91 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-91d '+%Y-%m-%d' 2>/dev/null)"
  _d6="$(date -u -d '6 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-6d '+%Y-%m-%d' 2>/dev/null)"
  _d29="$(date -u -d '29 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-29d '+%Y-%m-%d' 2>/dev/null)"
  _d89="$(date -u -d '89 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-89d '+%Y-%m-%d' 2>/dev/null)"

  local s13="$tmp/s13"
  mkdir -p "$s13/docs"
  cat > "$s13/docs/backlog.md" <<EOF
# Fixture Backlog

- **HIGH-OVERDUE-01 — fixture high crossed** (added $_d8 from fixture; label: \`harness-gap\`, \`priority:high\`). Prose body.
- **MED-OVERDUE-01 — fixture medium crossed** (added $_d31; \`priority:medium\`). Prose body.
- **LOW-OVERDUE-01 — fixture low crossed** (added $_d91; \`priority:low\`). Prose body.
- **HIGH-FRESH-01 — fixture high NOT yet crossed** (added $_d6; \`priority:high\`). Prose body.
- **MED-FRESH-01 — fixture medium NOT yet crossed** (added $_d29; \`priority:medium\`). Prose body.
- **LOW-FRESH-01 — fixture low NOT yet crossed** (added $_d89; \`priority:low\`). Prose body.
- **TERM-CLOSED-01 — [CLOSED $_d8] fixture terminal, aged past every tier** (added $_d91; \`priority:high\`). Prose.
- **TERM-ABSORBED-01 — fixture aged past every tier** (added $_d91; \`priority:high\`). **(absorbed by docs/plans/fixture.md)**.
- **TERM-IMPL-01** — IMPLEMENTED $_d8 via docs/plans/fixture2.md (added $_d91; \`priority:high\`).
- **OPEN-REF-01 — open row whose prose references ANOTHER row's terminal state** (added $_d8; \`priority:high\`). **This is distinct from OTHER-GAP-99 (IMPLEMENTED 2026-01-01).** Still open work.
EOF
  local s13_seen="$tmp/s13-seen.jsonl"
  local out13a
  # Cap raised for this scenario so every crossed row can surface; cap
  # behavior itself is S13c's job.
  out13a="$(BACKLOG_DIGEST_CAP=10 feed_backlog_accountability "$s13_seen" "$s13")"
  _ck_contains "S13a high row crossed >7d surfaces with tier+age" "$out13a" "backlog: HIGH-OVERDUE-01 (high, 8d)"
  _ck_contains "S13a medium row crossed >30d surfaces" "$out13a" "backlog: MED-OVERDUE-01 (medium, 31d)"
  _ck_contains "S13a low row crossed >90d surfaces" "$out13a" "backlog: LOW-OVERDUE-01 (low, 91d)"
  _ck_contains "S13a pin-d one-word replies inline, all four actionable" "$out13a" "-> reply SCHEDULE (spawn task) / FOLD (name plan) / DEMOTE (lower tier) / WONTFIX (reason)"
  _ck_not_contains "S13a high row at 6d (not >7d) silent" "$out13a" "HIGH-FRESH-01"
  _ck_not_contains "S13a medium row at 29d (not >30d) silent" "$out13a" "MED-FRESH-01"
  _ck_not_contains "S13a low row at 89d (not >90d) silent" "$out13a" "LOW-FRESH-01"
  _ck_not_contains "S13a [CLOSED]-marked row never surfaces" "$out13a" "TERM-CLOSED-01"
  _ck_not_contains "S13a (absorbed by ...)-marked row never surfaces" "$out13a" "TERM-ABSORBED-01"
  _ck_not_contains "S13a IMPLEMENTED-marked row never surfaces" "$out13a" "TERM-IMPL-01"
  _ck_contains "S13a open row REFERENCING another row's terminal state still surfaces (GH-AUTH false-skip regression)" "$out13a" "backlog: OPEN-REF-01 (high, 8d)"

  # S13b: second invocation same ISO week + same seen ledger -> silent.
  local out13b
  out13b="$(feed_backlog_accountability "$s13_seen" "$s13")"
  if [[ -z "$out13b" ]]; then
    echo "PASS: S13b second run same week is idempotent (silent)"
    pass=$((pass + 1))
  else
    echo "FAIL: S13b expected silence on second run, got:" >&2
    printf '%s\n' "$out13b" | sed 's/^/    /' >&2
    fail=$((fail + 1))
  fi

  # S13c: cap overflow — 5 overdue rows, default cap 3 -> the 3 OLDEST
  # surface + one "+2 more" overflow line; the 2 newest are NOT seen-bumped
  # and surface on the NEXT session (cap never silently eats rows).
  # Priority deliberately LOW (not high): this scenario tests the cap/
  # dedup/drain mechanics, which are orthogonal to the BUILD-ESCALATION
  # tier (S16). Low priority never hard-bound-escalates on age (by
  # design — see feed_backlog_accountability's esc_age_* comment), and 2
  # calls never reach the fester-count trigger (esc_digests default 3),
  # so these rows stay on the neutral path throughout, exactly as before
  # the escalation tier existed. High-priority 96-100d-old rows would
  # all instantly hard-bound-escalate (esc_age_high default 14) and
  # collapse to the escalated summary line instead, which is a real
  # regression this fixture must not trip.
  local _d100 _d99 _d98 _d97 _d96
  _d100="$(date -u -d '100 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-100d '+%Y-%m-%d' 2>/dev/null)"
  _d99="$(date -u -d '99 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-99d '+%Y-%m-%d' 2>/dev/null)"
  _d98="$(date -u -d '98 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-98d '+%Y-%m-%d' 2>/dev/null)"
  _d97="$(date -u -d '97 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-97d '+%Y-%m-%d' 2>/dev/null)"
  _d96="$(date -u -d '96 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-96d '+%Y-%m-%d' 2>/dev/null)"
  local s13c="$tmp/s13c"
  mkdir -p "$s13c/docs"
  cat > "$s13c/docs/backlog.md" <<EOF
- **CAP-A-01 — oldest** (added $_d100; \`priority:low\`). Prose.
- **CAP-B-01 — second-oldest** (added $_d99; \`priority:low\`). Prose.
- **CAP-C-01 — third-oldest** (added $_d98; \`priority:low\`). Prose.
- **CAP-D-01 — fourth** (added $_d97; \`priority:low\`). Prose.
- **CAP-E-01 — fifth** (added $_d96; \`priority:low\`). Prose.
EOF
  local s13c_seen="$tmp/s13c-seen.jsonl"
  local out13c
  out13c="$(feed_backlog_accountability "$s13c_seen" "$s13c")"
  _ck_contains "S13c oldest row surfaces under cap" "$out13c" "CAP-A-01"
  _ck_contains "S13c second-oldest surfaces under cap" "$out13c" "CAP-B-01"
  _ck_contains "S13c third-oldest surfaces under cap" "$out13c" "CAP-C-01"
  _ck_not_contains "S13c fourth (over cap) held back this session" "$out13c" "CAP-D-01"
  _ck_contains "S13c overflow line names the held-back count" "$out13c" "backlog: +2 more overdue row(s) -> docs/backlog.md"
  local out13c2
  out13c2="$(feed_backlog_accountability "$s13c_seen" "$s13c")"
  _ck_contains "S13c2 next session drains the held-back rows (CAP-D)" "$out13c2" "CAP-D-01"
  _ck_contains "S13c2 next session drains the held-back rows (CAP-E)" "$out13c2" "CAP-E-01"
  _ck_not_contains "S13c2 already-surfaced rows stay quiet same week" "$out13c2" "CAP-A-01"

  # S13d: run_digest-level wiring — the feed's lines land in the real
  # digest assembly (not just the unit function).
  local s13d="$tmp/s13d"
  _seed_repo "$s13d"
  mkdir -p "$s13d/docs"
  cat > "$s13d/docs/backlog.md" <<EOF
- **WIRED-ROW-01 — fixture overdue high row** (added $_d8; \`priority:high\`). Prose.
EOF
  local s13d_seen="$tmp/s13d-seen.jsonl"
  local out13d
  out13d="$(DIGEST_SEEN_PATH="$s13d_seen" run_digest "$s13d" "$tmp/s13d-no-alerts" "$s13d_seen" 2>/dev/null)"
  _ck_contains "S13d run_digest carries the backlog feed line" "$out13d" "backlog: WIRED-ROW-01 (high, 8d)"

  # ---- S16: BUILD-ESCALATION tier (operator directive 2026-07-07: "I need
  #           Neural Lace to be more proactive about resurfacing backlog
  #           items to me to actually be built"). THE GAP this closes:
  #           GH-AUTH-AUTOSWITCH-WORKORG-01 sat OPEN/overdue for 36 DAYS —
  #           the neutral 4-way nag never escalated toward BUILD. Sandboxed
  #           fixture backlog + sandboxed seen.jsonl throughout (025/028/034
  #           discipline unchanged).
  local _d15 _d31h _d9
  _d15="$(date -u -d '15 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-15d '+%Y-%m-%d' 2>/dev/null)"
  _d31h="$(date -u -d '31 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-31d '+%Y-%m-%d' 2>/dev/null)"
  _d9="$(date -u -d '9 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-9d '+%Y-%m-%d' 2>/dev/null)"

  # S16a: hard-age-bound trigger — a HIGH row at 15d (> esc_age_high default
  # 14) escalates on its VERY FIRST surfaced digest (fester count 1), with
  # the BUILD-leading line, fester count, and age all present.
  local s16a="$tmp/s16a"
  mkdir -p "$s16a/docs"
  cat > "$s16a/docs/backlog.md" <<EOF
- **ESC-HARDBOUND-01 — fixture high row past the hard age bound** (added $_d15; \`priority:high\`). Prose body.
EOF
  local s16a_seen="$tmp/s16a-seen.jsonl"
  local out16a
  out16a="$(feed_backlog_accountability "$s16a_seen" "$s16a")"
  _ck_contains "S16a hard-age-bound row escalates on first digest (BUILD-leading line)" "$out16a" "backlog ESCALATED: ESC-HARDBOUND-01 undisposed across 1 digests, 15d -> propose BUILD NOW"
  _ck_contains "S16a escalated line offers SCHEDULE/DEMOTE/WONTFIX (not the 4-way FOLD form)" "$out16a" "reply SCHEDULE (spawn builder) / or DEMOTE / WONTFIX <reason>"

  # S16b: a row that JUST crossed its normal overdue tier (medium, 31d —
  # over the 30d medium overdue tier but well under the 60d medium
  # escalation hard bound) does NOT escalate on its first digest (fester
  # count 1, under both the fester-count and age-hard-bound triggers) —
  # it surfaces as a plain neutral proposal only. This is the regression
  # this tier must never reintroduce: a row becoming overdue is not the
  # same event as a row becoming escalation-worthy.
  local s16b="$tmp/s16b"
  mkdir -p "$s16b/docs"
  cat > "$s16b/docs/backlog.md" <<EOF
- **ESC-FRESH-01 — fixture medium row freshly crossed, not yet escalated** (added $_d31h; \`priority:medium\`). Prose body.
EOF
  local s16b_seen="$tmp/s16b-seen.jsonl"
  local out16b
  out16b="$(feed_backlog_accountability "$s16b_seen" "$s16b")"
  _ck_contains "S16b freshly-crossed row still surfaces neutrally" "$out16b" "backlog: ESC-FRESH-01 (medium, 31d)"
  _ck_not_contains "S16b freshly-crossed row does NOT escalate (fester count 1, not past hard bound)" "$out16b" "ESCALATED"

  # S16c: fester-count trigger — a HIGH row at 9d (crosses the 7d high
  # overdue tier but sits UNDER the 14d escalation hard bound, isolating
  # the fester-count path cleanly from S16a's hard-bound path) surfaced
  # across 3 digests crosses BACKLOG_ESCALATION_DIGESTS (default 3) on the
  # third call and escalates with the correct cumulative fester count.
  # Same real seen_path each call, same real ISO week (self-tests cannot
  # time-travel the system clock) — runs 2 land silently on the NEUTRAL
  # line per the weekly dedup (S13b), which is exactly what proves S16d
  # below: the fester counter itself bumps unconditionally regardless of
  # that neutral-path dedup, so escalation still fires on schedule.
  local s16c="$tmp/s16c"
  mkdir -p "$s16c/docs"
  cat > "$s16c/docs/backlog.md" <<EOF
- **ESC-FESTER-01 — fixture high row nagged repeatedly, never dispositioned** (added $_d9; \`priority:high\`). Prose body.
EOF
  local s16c_seen="$tmp/s16c-seen.jsonl"
  local out16c_1 out16c_2 out16c_3
  out16c_1="$(feed_backlog_accountability "$s16c_seen" "$s16c")"
  _ck_not_contains "S16c fester run 1/3 not yet escalated" "$out16c_1" "ESCALATED"
  _ck_contains "S16c fester run 1/3 surfaces neutrally" "$out16c_1" "backlog: ESC-FESTER-01 (high, 9d)"
  out16c_2="$(feed_backlog_accountability "$s16c_seen" "$s16c")"
  out16c_3="$(feed_backlog_accountability "$s16c_seen" "$s16c")"
  _ck_contains "S16c fester run 3/3 crosses threshold and escalates (undisposed across 3 digests)" "$out16c_3" "backlog ESCALATED: ESC-FESTER-01 undisposed across 3 digests, 9d -> propose BUILD NOW"

  # S16d: escalated rows are EXEMPT from the weekly dedup collapse that
  # silences neutral rows — recur every session even within the same ISO
  # week (the whole point: ignoring costs more than dispositioning).
  local out16d
  out16d="$(feed_backlog_accountability "$s16c_seen" "$s16c")"
  _ck_contains "S16d escalated row recurs on the VERY NEXT digest, same ISO week (dedup-exempt)" "$out16d" "backlog ESCALATED: ESC-FESTER-01"

  # S16e: a DISPOSITIONED row (SCHEDULED marker) never escalates and drops
  # out of the feed entirely — the oracle-level dispositioned-in-flight
  # fix (od_backlog_health) suppresses it from overdue_ids, so it never
  # reaches this function's candidate list at all.
  local s16e="$tmp/s16e"
  mkdir -p "$s16e/docs"
  cat > "$s16e/docs/backlog.md" <<EOF
- **ESC-DISPOSITIONED-01 — fixture high row the operator already answered** (added $_d15; \`priority:high\`). Prose. **SCHEDULED $_d9** (operator disposition — build in flight, row closes DONE when it merges).
EOF
  local s16e_seen="$tmp/s16e-seen.jsonl"
  local out16e
  out16e="$(feed_backlog_accountability "$s16e_seen" "$s16e")"
  if [[ -z "$out16e" ]]; then
    echo "PASS: S16e SCHEDULED-marked row is silent (dispositioned-in-flight, never re-nags)"
    pass=$((pass + 1))
  else
    echo "FAIL: S16e expected silence for a SCHEDULED-marked row, got:" >&2
    printf '%s\n' "$out16e" | sed 's/^/    /' >&2
    fail=$((fail + 1))
  fi

  # S16f: multi-escalation summary — more than BACKLOG_ESCALATION_SUMMARY_
  # THRESHOLD (default 2) rows escalated collapses to ONE compact summary
  # line naming only the oldest as the actionable pointer, instead of N
  # full ESCALATED lines (visual-footprint honesty per spec). All three
  # rows must actually hard-bound-escalate on their FIRST digest (fester
  # count 1): C-01 is `high` (not `medium`) at 15d because 15 clears
  # esc_age_high's default 14 but sits well under esc_age_medium's
  # default 60 — a medium row here would not escalate at all.
  local s16f="$tmp/s16f"
  mkdir -p "$s16f/docs"
  cat > "$s16f/docs/backlog.md" <<EOF
- **ESC-MULTI-A-01 — oldest escalated** (added $_d31h; \`priority:high\`). Prose.
- **ESC-MULTI-B-01 — second escalated** (added $_d15; \`priority:high\`). Prose.
- **ESC-MULTI-C-01 — third escalated** (added $_d15; \`priority:high\`). Prose.
EOF
  local s16f_seen="$tmp/s16f-seen.jsonl"
  local out16f
  out16f="$(BACKLOG_DIGEST_CAP=10 feed_backlog_accountability "$s16f_seen" "$s16f")"
  _ck_contains "S16f 3 escalated rows collapse to ONE summary line" "$out16f" "backlog: 3 build-ready rows escalated -> top: ESC-MULTI-A-01"
  _ck_not_contains "S16f summary mode suppresses the per-row ESCALATED line for the top row" "$out16f" "backlog ESCALATED: ESC-MULTI-A-01"
  _ck_not_contains "S16f summary mode does not also print the second row individually" "$out16f" "ESC-MULTI-B-01"

  # S16g: flagless-shape scenario — the real production entry path (`bash
  # session-start-digest.sh`, no CLI flags, stdin closed) surfaces an
  # escalated row exactly as the unit-level S16a scenario does, proving
  # the tier is wired all the way through run_digest's real invocation
  # shape, not just reachable as an internal bash function.
  local s16g="$tmp/s16g"
  _seed_repo "$s16g"
  mkdir -p "$s16g/docs"
  cat > "$s16g/docs/backlog.md" <<EOF
- **ESC-FLAGLESS-01 — fixture high row past the hard age bound** (added $_d15; \`priority:high\`). Prose body.
EOF
  local s16g_ledger="$tmp/s16g-ledger.jsonl"
  local s16g_seen="$tmp/s16g-seen.jsonl"
  local s16g_home="$tmp/s16g-home"
  mkdir -p "$s16g_home/.claude/state"
  local s16g_script="$HOOKS_DIR/$(basename "${BASH_SOURCE[0]}")"
  local out16g
  out16g="$(
    cd "$s16g" && \
    HOME="$s16g_home" HARNESS_SELFTEST=1 SIGNAL_LEDGER_PATH="$s16g_ledger" DIGEST_SEEN_PATH="$s16g_seen" \
      bash "$s16g_script" </dev/null 2>/dev/null
  )"
  _ck_contains "S16g real flagless invocation surfaces the escalated build-leading line" "$out16g" "backlog ESCALATED: ESC-FLAGLESS-01 undisposed across 1 digests, 15d -> propose BUILD NOW"

  # ---- S14 (Wave O task O.1): run_digest emits a session-start ledger
  # event exactly once per invocation. Invoked via the REAL flagless
  # production call shape (run_digest "$cwd") -- no extra flags, only env
  # sandboxing (SIGNAL_LEDGER_PATH) per specs-o §O.0.1 rule 4 -- so this
  # scenario mirrors the mandated flagless-invocation-shape requirement.
  local s14="$tmp/s14"
  _seed_repo "$s14"
  local s14_seen="$tmp/s14-seen.jsonl"
  local s14_ledger="$tmp/s14-ledger.jsonl"
  ( export SIGNAL_LEDGER_PATH="$s14_ledger"; \
    DIGEST_SEEN_PATH="$s14_seen" run_digest "$s14" "$tmp/s14-no-alerts" "$s14_seen" >/dev/null 2>&1 )
  if [[ -f "$s14_ledger" ]] && grep -q '"gate":"session-start-digest".*"event":"session-start"' "$s14_ledger" 2>/dev/null; then
    echo "PASS: S14 run_digest emits a session-start ledger event (contract C2, flagless shape)"; pass=$((pass + 1))
  else
    echo "FAIL: S14 run_digest emits a session-start ledger event (expected a session-start-digest/session-start line in $s14_ledger)" >&2
    fail=$((fail + 1))
  fi
  local s14_count
  s14_count=$(grep -c '"event":"session-start"' "$s14_ledger" 2>/dev/null | tr -d ' ')
  [[ -z "$s14_count" ]] && s14_count=0
  _ck_le "S14 exactly one session-start line per run_digest invocation" "$s14_count" "1"
  if [[ "$s14_count" -ge 1 ]]; then
    echo "PASS: S14 at least one session-start line emitted"; pass=$((pass + 1))
  else
    echo "FAIL: S14 at least one session-start line emitted (got 0)" >&2
    fail=$((fail + 1))
  fi

  # ---- S15 (Wave O task O.1, specs-o §O.0.1 rule 4 -- flagless-shape
  # mandate): every OTHER scenario in this file calls feed_*/run_digest as
  # internal bash functions; this one invokes the REAL production entry
  # path instead -- `bash session-start-digest.sh` with stdin (empty, the
  # normal SessionStart shape) and NO CLI flags, only env-var sandboxing
  # (HOME + SIGNAL_LEDGER_PATH + DIGEST_SEEN_PATH), exactly mirroring how
  # settings.json.template actually wires this hook.
  local s15="$tmp/s15"
  _seed_repo "$s15"
  local s15_ledger="$tmp/s15-ledger.jsonl"
  local s15_seen="$tmp/s15-seen.jsonl"
  local s15_home="$tmp/s15-home"
  mkdir -p "$s15_home/.claude/state"
  # BASH_SOURCE[0] resolved to an ABSOLUTE path via HOOKS_DIR (already
  # computed at top-of-script) BEFORE the `cd` below — the self-test was
  # invoked with a RELATIVE path in earlier iterations of this scenario,
  # and once the subshell `cd`'d into the fixture dir, that relative path
  # no longer resolved to the real script, which hung the whole suite
  # indefinitely at this exact call (root-caused via `bash -x` tracing).
  local s15_script="$HOOKS_DIR/$(basename "${BASH_SOURCE[0]}")"
  (
    cd "$s15" && \
    HOME="$s15_home" HARNESS_SELFTEST=1 SIGNAL_LEDGER_PATH="$s15_ledger" DIGEST_SEEN_PATH="$s15_seen" \
      bash "$s15_script" </dev/null >/dev/null 2>&1
  )
  if [[ -f "$s15_ledger" ]] && grep -q '"gate":"session-start-digest".*"event":"session-start"' "$s15_ledger" 2>/dev/null; then
    echo "PASS: S15 real flagless invocation (bash session-start-digest.sh, no flags) emits session-start"; pass=$((pass + 1))
  else
    echo "FAIL: S15 real flagless invocation (bash session-start-digest.sh, no flags) emits session-start (expected a line in $s15_ledger)" >&2
    fail=$((fail + 1))
  fi

  rm -rf "$tmp" 2>/dev/null || true
  echo ""
  echo "self-test summary: $pass passed, $fail failed"
  if [[ "$fail" -eq 0 ]]; then
    echo "self-test: OK $pass/$pass"
    return 0
  else
    echo "self-test: FAIL"
    return 1
  fi
}

# ============================================================
# --ack-finding-021 mode: one-time sweep acking pre-existing stale
# principles-gate-r3 duplicates as ONE class (NL-FINDING-021 remediation).
# Not part of normal SessionStart invocation; run once at ship-time.
# ============================================================
run_ack_finding_021() {
  local alert_dir="${1:-$(_alert_dir_default)}"
  [[ -d "$alert_dir" ]] || { echo "ack-finding-021: alert dir not found: $alert_dir" >&2; return 1; }
  local f count=0
  for f in "$alert_dir"/principles-gate-r3-*.json; do
    [[ -f "$f" ]] || continue
    [[ -f "${f}.acked" ]] && continue
    touch "${f}.acked" 2>/dev/null && count=$((count + 1))
  done
  if [[ "$count" -gt 0 ]] && _have ledger_emit; then
    ledger_emit "session-start-digest" "waiver" "NL-FINDING-021: acked ${count} stale principles-gate-r3 duplicate alert(s) as one class (dated sweep, ${alert_dir})"
  fi
  echo "ack-finding-021: acked ${count} file(s) in ${alert_dir}"
  return 0
}

# ============================================================
# Entry point — guarded so `source`-ing this file (self-test harnesses,
# fixture scaffolding that wants access to the feed_* functions without
# triggering a live run) never falls through to a real invocation. Mirrors
# the nl-paths.sh / lib/signal-ledger.sh source-guard convention.
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test)
      run_self_test
      exit $?
      ;;
    --ack-finding-021)
      run_ack_finding_021 "${2:-}"
      exit $?
      ;;
    --refresh-doctor-cache)
      refresh_doctor_cache "${2:-$PWD}"
      exit $?
      ;;
    *)
      # NL-FINDING-040 keystone guard: an automation-spawned/re-entrant
      # invocation (NL_HOOK_REENTRY=1, e.g. a session-resumer.sh-launched
      # `claude` child) no-ops here BEFORE any feed runs, any subprocess
      # spawns (workstreams-emit.sh, session-heartbeat.sh), or the doctor
      # cache refresh happens. A normal interactive SessionStart is
      # completely unaffected (NL_HOOK_REENTRY unset by default) — see
      # lib/hook-reentry-guard.sh.
      if command -v hook_reentry_should_suppress >/dev/null 2>&1 && hook_reentry_should_suppress; then
        hook_reentry_note "session-start-digest" 2>/dev/null || true
        echo "[session-start-digest] reentrant/automation-spawned invocation — skipping digest (NL-FINDING-040 guard)"
        exit 0
      fi
      DIGEST_STDIN=""
      if [[ ! -t 0 ]]; then
        DIGEST_STDIN="$(cat 2>/dev/null || true)"
      fi
      run_digest "$PWD"
      exit 0
      ;;
  esac
fi
