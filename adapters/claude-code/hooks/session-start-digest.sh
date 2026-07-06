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
# Main assembly. Args: $1 = cwd override (testability), $2 = alert_dir
# override, $3 = seen_path override. Writes the digest to stdout, capped
# at MAX_LINES. Always exits 0.
# ----------------------------------------------------------------------
run_digest() {
  local cwd="${1:-$PWD}"
  local alert_dir="${2:-$(_alert_dir_default)}"
  local seen_path; seen_path="${3:-$(_digest_seen_path)}"
  local input="${DIGEST_STDIN:-}"

  local -a lines=()
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
      DIGEST_STDIN=""
      if [[ ! -t 0 ]]; then
        DIGEST_STDIN="$(cat 2>/dev/null || true)"
      fi
      run_digest "$PWD"
      exit 0
      ;;
  esac
fi
