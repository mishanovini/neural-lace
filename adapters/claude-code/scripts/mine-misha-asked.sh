#!/usr/bin/env bash
# mine-misha-asked.sh — System 1 of the drift-backlog + harness-evaluator pair.
#
# Walks Claude Code transcript history under ~/.claude/projects/*/*.jsonl,
# extracts imperative-mood asks (the things Misha told the orchestrator to
# do), classifies them, searches repo state for a satisfying artifact, and
# writes any ask older than DRIFT_THRESHOLD_DAYS without a satisfying
# artifact to docs/backlog/misha-asked-for.json.
#
# Performance: the heavy lifting (paragraph split + imperative classification
# + dedup) all happens in two awk passes + jq, NOT in per-record bash loops.
# Artifact search uses bash but runs only on the deduped unique set, which
# is far smaller (hundreds, not thousands of rows).
#
# Usage:
#   bash adapters/claude-code/scripts/mine-misha-asked.sh           # default scan
#   bash adapters/claude-code/scripts/mine-misha-asked.sh --rescan  # force full re-scan
#   bash adapters/claude-code/scripts/mine-misha-asked.sh --recent-days 7
#   bash adapters/claude-code/scripts/mine-misha-asked.sh --output <path>
#   bash adapters/claude-code/scripts/mine-misha-asked.sh --self-test
#
# Output: docs/backlog/misha-asked-for.json (relative to repo root).

set -uo pipefail

# ---- config (env-overridable) ---------------------------------------------
DRIFT_THRESHOLD_DAYS="${DRIFT_THRESHOLD_DAYS:-14}"
RECENT_DAYS="${RECENT_DAYS:-}"
TRANSCRIPTS_ROOT="${TRANSCRIPTS_ROOT:-$HOME/.claude/projects}"
MIN_ASK_LEN="${MIN_ASK_LEN:-40}"
MAX_ASK_LEN="${MAX_ASK_LEN:-500}"
MAX_ARTIFACT_SEARCH="${MAX_ARTIFACT_SEARCH:-500}"  # cap artifact-search calls
PROJECT_FILTER="${PROJECT_FILTER:-}"  # if set, only emit asks from sessions matching this substring

# ---- args ----
SELF_TEST=0
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rescan) shift ;;   # noop placeholder; full scan is the default
    --recent-days) RECENT_DAYS="$2"; shift 2 ;;
    --output) OUTPUT_PATH="$2"; shift 2 ;;
    --project-filter) PROJECT_FILTER="$2"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    --help|-h)
      sed -n '2,25p' "$0"
      exit 0 ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 1 ;;
  esac
done

# ---- locate self + helpers ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib/imperative-classifier.sh"
if [[ ! -f "$LIB" ]]; then
  echo "ERROR: helper not found: $LIB" >&2
  exit 1
fi
# shellcheck source=lib/imperative-classifier.sh
source "$LIB"

# ---- prereqs ----
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not on PATH: $1" >&2
    exit 1
  fi
}
require_cmd jq
require_cmd git
require_cmd awk

# ---- repo root + output path -----------------------------------------------
find_repo_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}

REPO_ROOT="$(find_repo_root)"
if [[ -z "$OUTPUT_PATH" ]]; then
  # .claude/state/ is gitignored — drift backlog contains machine-specific
  # paths and user-message content, so it must NOT be committed to the
  # harness repo. Per-machine operational state belongs in .claude/state/.
  OUTPUT_PATH="$REPO_ROOT/.claude/state/drift-backlog/misha-asked-for.json"
fi

# ---- self-test --------------------------------------------------------------
run_self_test() {
  local failed=0
  echo "[self-test] imperative_match should fire on canonical imperatives"
  for phrase in \
    "we should add a new hook" \
    "please run the test suite" \
    "I want you to fix the redirect" \
    "let's build the evaluator" \
    "make sure the gate fires" \
    "from now on always commit before pushing"; do
    if ! imperative_match "$phrase" >/dev/null 2>&1; then
      echo "[self-test] FAIL: imperative not matched: '$phrase'"; failed=1
    fi
  done

  echo "[self-test] imperative_match should NOT fire on non-imperatives"
  for phrase in \
    "the weather is nice today" \
    "I read the file and it was empty"; do
    if imperative_match "$phrase" >/dev/null 2>&1; then
      echo "[self-test] FAIL: false positive on: '$phrase'"; failed=1
    fi
  done

  echo "[self-test] classify_ask sanity"
  local got
  got=$(classify_ask "we should consider rewriting this")
  [[ "$got" == "recommendation" ]] || { echo "[self-test] FAIL: expected recommendation, got $got"; failed=1; }
  got=$(classify_ask "going forward, always tag commits")
  [[ "$got" == "aspirational" ]] || { echo "[self-test] FAIL: expected aspirational, got $got"; failed=1; }
  got=$(classify_ask 'Misha quoted: "we should fix this"')
  [[ "$got" == "quote-not-ask" ]] || { echo "[self-test] FAIL: expected quote-not-ask, got $got"; failed=1; }
  got=$(classify_ask "please add the new endpoint")
  [[ "$got" == "explicit-task" ]] || { echo "[self-test] FAIL: expected explicit-task, got $got"; failed=1; }

  echo "[self-test] artifact_search returns 1 when no match"
  if artifact_search "completely-nonexistent-string-xyzzy-12345" >/dev/null 2>&1; then
    echo "[self-test] FAIL: artifact_search should return 1 for nonexistent text"; failed=1
  fi

  if [[ $failed -eq 0 ]]; then
    echo "[self-test] all checks passed"
    return 0
  else
    echo "[self-test] FAILED ($failed checks)"
    return 2
  fi
}

# ---- artifact search --------------------------------------------------------
# For a given ask text, search repo state for an artifact that plausibly
# satisfies the ask. False positives expected; surface in weekly review.
artifact_search() {
  local text="$1"
  local keyword
  keyword=$(printf '%s\n' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/^[[:space:]]*(please |we should |we need to |i want you to |i need you to |let'\''s |can you |could you |make sure )+//' \
    | sed -E 's/[^a-z0-9 -]/ /g' \
    | tr -s ' ' \
    | awk '{
        i = 1
        if ($i == "a" || $i == "an" || $i == "the" || $i == "to" || $i == "of") i++
        n = i + 4
        out = ""
        for (j = i; j <= n && j <= NF; j++) {
          if (length($j) >= 3) out = out " " $j
        }
        print out
      }' \
    | sed 's/^ //')

  if [[ -z "$keyword" || ${#keyword} -lt 8 ]]; then
    return 1
  fi

  local commit_hit
  commit_hit=$(cd "$REPO_ROOT" && git log --oneline -n 1000 --grep="$keyword" --ignore-case 2>/dev/null | head -1)
  if [[ -n "$commit_hit" ]]; then
    printf 'commit: %s\n' "$commit_hit"
    return 0
  fi

  local branch_hit
  branch_hit=$(cd "$REPO_ROOT" && git branch -a 2>/dev/null | grep -iF "$(echo "$keyword" | tr ' ' '-')" | head -1 | sed 's/^[ *]*//')
  if [[ -n "$branch_hit" ]]; then
    printf 'branch: %s\n' "$branch_hit"
    return 0
  fi

  if [[ -f "$REPO_ROOT/docs/failure-modes.md" ]]; then
    local fm_hit
    fm_hit=$(grep -i -m1 "$keyword" "$REPO_ROOT/docs/failure-modes.md" 2>/dev/null | head -1 | cut -c1-100)
    if [[ -n "$fm_hit" ]]; then
      printf 'failure-mode: %s\n' "$fm_hit"
      return 0
    fi
  fi

  if [[ -f "$REPO_ROOT/docs/backlog.md" ]]; then
    if grep -qi "$keyword" "$REPO_ROOT/docs/backlog.md" 2>/dev/null; then
      printf 'backlog-tracked: %s\n' "$keyword"
      return 0
    fi
  fi

  return 1
}

# ---- main scan --------------------------------------------------------------
do_scan() {
  echo "[mine] scanning transcripts under: $TRANSCRIPTS_ROOT"
  if [[ ! -d "$TRANSCRIPTS_ROOT" ]]; then
    echo "ERROR: transcripts root does not exist: $TRANSCRIPTS_ROOT" >&2
    exit 1
  fi

  local find_args=("$TRANSCRIPTS_ROOT" -name "*.jsonl" -type f)
  if [[ -n "$RECENT_DAYS" ]]; then
    find_args+=("-mtime" "-$RECENT_DAYS")
  fi

  # Project filter — find only transcripts under matching project dirs.
  local find_filter=""
  if [[ -n "$PROJECT_FILTER" ]]; then
    find_filter="$PROJECT_FILTER"
    echo "[mine] applying project filter: $find_filter"
  fi

  local jsonl_count
  if [[ -n "$find_filter" ]]; then
    jsonl_count=$(find "${find_args[@]}" 2>/dev/null | grep -F "$find_filter" | wc -l | tr -d ' ')
  else
    jsonl_count=$(find "${find_args[@]}" 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "[mine] found $jsonl_count transcript files"
  if [[ "$jsonl_count" -eq 0 ]]; then
    echo "[mine] no transcripts to scan; exiting"
    exit 0
  fi

  local tmp_raw tmp_paras tmp_imps tmp_dedup tmp_final
  tmp_raw=$(mktemp -t misha-raw.XXXXXX)
  tmp_paras=$(mktemp -t misha-paras.XXXXXX)
  tmp_imps=$(mktemp -t misha-imps.XXXXXX)
  tmp_dedup=$(mktemp -t misha-dedup.XXXXXX)
  tmp_final=$(mktemp -t misha-final.XXXXXX)
  # Export tmp paths so the EXIT trap (which runs after `local` scope ends) can see them
  export _MM_TMP1="$tmp_raw" _MM_TMP2="$tmp_paras" _MM_TMP3="$tmp_imps" _MM_TMP4="$tmp_dedup" _MM_TMP5="$tmp_final"
  trap 'rm -f "${_MM_TMP1:-}" "${_MM_TMP2:-}" "${_MM_TMP3:-}" "${_MM_TMP4:-}" "${_MM_TMP5:-}"' EXIT

  # ---- pass 1: extract (sess, ts, project, content) into one TSV per user message ----
  echo "[mine] pass 1: extracting user messages"
  local listing
  if [[ -n "$find_filter" ]]; then
    listing=$(find "${find_args[@]}" 2>/dev/null | grep -F "$find_filter")
  else
    listing=$(find "${find_args[@]}" 2>/dev/null)
  fi
  echo "$listing" | while read -r jsonl; do
    [[ -z "$jsonl" ]] && continue
    local sess project
    sess=$(basename "$jsonl" .jsonl)
    # project = the directory name under ~/.claude/projects/
    project=$(basename "$(dirname "$jsonl")" | sed -E 's/^C--Users-misha-//' | sed -E 's/^claude-projects-//')
    jq -r --arg sess "$sess" --arg project "$project" \
      'select(.type=="user" and (.message.content | type == "string"))
        | [$sess, (.timestamp // ""), $project, (.message.content | gsub("\n"; " ⏎ "))] | @tsv' \
      "$jsonl" 2>/dev/null
  done > "$tmp_raw"

  local raw_count
  raw_count=$(wc -l < "$tmp_raw" | tr -d ' ')
  echo "[mine] extracted $raw_count user-message records"

  # ---- pass 2: split into paragraphs + filter to imperatives ----
  # awk does the paragraph splitting (on " ⏎  ⏎ " — double-newline-equivalent)
  # and applies the imperative regex inline. Outputs TSV per matched paragraph.
  echo "[mine] pass 2: classifying paragraphs"
  awk -F'\t' '
    BEGIN {
      # Imperative trigger regex. Mirror what imperative_match does, in awk.
      IGNORECASE = 1
      trig = "(i want you to|i need you to|please [a-z]+|we should|we need to|let'\''s (build|do|add|fix|ship|create|implement|wire)|make sure|don'\''t forget to|remember to|you (should|need to|must|have to)|can you (please )?|could you (please )?|next time|going forward|from now on|always [a-z]+|never [a-z]+)"
    }
    {
      sess = $1
      ts = $2
      project = $3
      content = $4
      # Split paragraphs on " ⏎  ⏎ " (double newline) — best-effort
      n = split(content, paras, " ⏎  ⏎ ")
      for (i = 1; i <= n; i++) {
        p = paras[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
        if (length(p) < '"$MIN_ASK_LEN"') continue
        if (length(p) > '"$MAX_ASK_LEN"') p = substr(p, 1, '"$MAX_ASK_LEN"')
        # Skip code fence lines
        if (p ~ /^```/) continue
        # Skip pure-conversational responses (approvals, acknowledgements)
        if (p ~ /^(yes|sure|approved|ok|okay|sounds good|great|perfect|got it|thanks|thank you|nice|cool|fine)([[:space:],.!]|$)/) continue
        # Apply imperative trigger
        if (match(p, trig)) {
          trigger = substr(p, RSTART, RLENGTH)
          gsub(/\t/, " ", p)
          gsub(/\t/, " ", trigger)
          print sess "\t" ts "\t" project "\t" trigger "\t" p
        }
      }
    }
  ' "$tmp_raw" > "$tmp_paras"

  local para_count
  para_count=$(wc -l < "$tmp_paras" | tr -d ' ')
  echo "[mine] $para_count imperative-bearing paragraphs"

  if [[ "$para_count" -eq 0 ]]; then
    echo "[mine] no imperative paragraphs found; writing empty output and exiting"
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg threshold "$DRIFT_THRESHOLD_DAYS" '{
      meta: {generated_at: $now, drift_threshold_days: ($threshold | tonumber), total_unique_asks: 0, scan_root: "'"$TRANSCRIPTS_ROOT"'"},
      summary: {drift: 0, satisfied: 0, recent_pending: 0, non_task_class: 0},
      drift_items: [], satisfied_items: [], recent_pending: [], non_task_samples: []
    }' > "$OUTPUT_PATH"
    echo "[mine] wrote (empty): $OUTPUT_PATH"
    return 0
  fi

  # ---- pass 3: classify (quote-not-ask filter, aspirational, etc) + normalize hash ----
  echo "[mine] pass 3: classifying + hashing"
  awk -F'\t' '
    BEGIN { IGNORECASE = 1 }
    function classify(text,    klass) {
      if (text ~ /"[^"]*(we should|please|i want you to|make sure)[^"]*"/) return "quote-not-ask"
      if (text ~ /going forward|from now on|always [a-z]+|never [a-z]+|in future|next time/) return "aspirational"
      if (text ~ /we should consider|ideally|might want to|would be nice|nice to have|in theory/) return "recommendation"
      if (text ~ /(^|[.;])[[:space:]]*(also|btw|by the way|oh and|one more thing|side note)[[:space:]]+/) return "dropped-suggestion"
      return "explicit-task"
    }
    function normalize(text,    n) {
      n = tolower(text)
      gsub(/[^a-z0-9 ]/, " ", n)
      gsub(/[ ]+/, " ", n)
      return substr(n, 1, 200)
    }
    {
      sess = $1; ts = $2; project = $3; trigger = $4; ask = $5
      klass = classify(ask)
      if (klass == "quote-not-ask") next
      norm = normalize(ask)
      print sess "\t" ts "\t" project "\t" trigger "\t" klass "\t" norm "\t" ask
    }
  ' "$tmp_paras" > "$tmp_imps"

  local imp_count
  imp_count=$(wc -l < "$tmp_imps" | tr -d ' ')
  echo "[mine] $imp_count asks after classification filter"

  # ---- pass 4: dedup by normalized-text-prefix (awk one-pass) ----
  echo "[mine] pass 4: dedup + aggregating repetition counts"
  # Field layout from pass 3: sess, ts, project, trigger, klass, norm, ask
  sort -t $'\t' -k6,6 -k2,2 "$tmp_imps" | awk -F'\t' '
    function flush() {
      if (key != "") {
        # Compose sessions JSON array
        sess_json = "["
        first = 1
        for (s in sessions) {
          if (!first) sess_json = sess_json ","
          sess_json = sess_json "\"" s "\""
          first = 0
        }
        sess_json = sess_json "]"
        # Compose projects JSON array
        proj_json = "["
        first = 1
        for (pr in projects) {
          if (!first) proj_json = proj_json ","
          proj_json = proj_json "\"" pr "\""
          first = 0
        }
        proj_json = proj_json "]"
        print first_ts "\t" last_ts "\t" count "\t" sess_json "\t" proj_json "\t" trigger "\t" klass "\t" sample_ask
      }
    }
    {
      sess = $1; ts = $2; project = $3; trigger_in = $4; klass_in = $5; nkey = $6; ask = $7
      if (nkey != key) {
        flush()
        key = nkey
        first_ts = ts
        count = 0
        delete sessions
        delete projects
        sample_ask = ask
        trigger = trigger_in
        klass = klass_in
      }
      last_ts = ts
      count++
      sessions[sess] = 1
      projects[project] = 1
    }
    END { flush() }
  ' > "$tmp_dedup"

  local uniq_count
  uniq_count=$(wc -l < "$tmp_dedup" | tr -d ' ')
  echo "[mine] $uniq_count unique asks after dedup"

  # ---- pass 5: artifact search + drift computation (the only slow per-row step) ----
  echo "[mine] pass 5: artifact search + drift age (capped at $MAX_ARTIFACT_SEARCH)"
  local now_epoch
  now_epoch=$(date +%s)
  local n_drift=0 n_satisfied=0 n_recent=0 n_nontask=0
  local processed=0

  # IMPORTANT: we cap artifact-search to keep the scan bounded.
  # Anything beyond the cap is just emitted with status=untested.
  while IFS=$'\t' read -r first_ts last_ts count sessions projects trigger klass ask; do
    processed=$((processed+1))

    # Compute age
    local age_days="null"
    if [[ -n "$first_ts" ]]; then
      local ts_epoch
      ts_epoch=$(date -d "$first_ts" +%s 2>/dev/null || echo "")
      if [[ -n "$ts_epoch" ]]; then
        age_days=$(( (now_epoch - ts_epoch) / 86400 ))
      fi
    fi

    # Hash from python-free path: take first 12 hex of md5(ask)
    local h
    h=$(printf '%s' "$ask" | md5sum 2>/dev/null | cut -c1-12)

    # Artifact search ONLY for explicit-task class AND within cap
    local artifact_evidence=""
    local status=""
    if [[ "$klass" == "explicit-task" ]]; then
      if [[ "$processed" -le "$MAX_ARTIFACT_SEARCH" ]]; then
        artifact_evidence=$(artifact_search "$ask" 2>/dev/null || true)
      fi
      if [[ -n "$artifact_evidence" ]]; then
        status="satisfied"; n_satisfied=$((n_satisfied+1))
      elif [[ "$age_days" != "null" && "$age_days" != "" && "$age_days" -gt "$DRIFT_THRESHOLD_DAYS" ]] 2>/dev/null; then
        status="drift"; n_drift=$((n_drift+1))
      else
        status="recent-pending"; n_recent=$((n_recent+1))
      fi
    else
      status="non-task-class"; n_nontask=$((n_nontask+1))
    fi

    # Build JSON object via jq for safe escaping
    jq -nc \
      --arg hash "$h" \
      --arg first_ts "$first_ts" --arg last_ts "$last_ts" \
      --argjson rep "$count" \
      --argjson sess "$sessions" \
      --argjson proj "$projects" \
      --arg trigger "$trigger" --arg klass "$klass" \
      --arg ask "$ask" --arg artifact "$artifact_evidence" \
      --arg status "$status" \
      --argjson age "$([[ "$age_days" == "null" ]] && echo "null" || echo "$age_days")" \
      '{hash:$hash, first_ts:$first_ts, last_ts:$last_ts, repetition_count:$rep,
        sessions:$sess, source_projects:$proj, trigger:$trigger, classification:$klass,
        ask:$ask, artifact_evidence:$artifact, status:$status, age_days:$age}' \
      >> "$tmp_final"

    if (( processed % 50 == 0 )); then
      echo "[mine]   processed $processed / $uniq_count"
    fi
  done < "$tmp_dedup"

  # ---- compose final output ---------------------------------------------------
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  jq -s --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg threshold "$DRIFT_THRESHOLD_DAYS" \
        --arg total "$uniq_count" \
    '{
      meta: {
        generated_at: $now,
        drift_threshold_days: ($threshold | tonumber),
        total_unique_asks: ($total | tonumber),
        scan_root: "'"$TRANSCRIPTS_ROOT"'"
      },
      summary: {
        drift: ([.[] | select(.status == "drift")] | length),
        satisfied: ([.[] | select(.status == "satisfied")] | length),
        recent_pending: ([.[] | select(.status == "recent-pending")] | length),
        non_task_class: ([.[] | select(.status == "non-task-class")] | length)
      },
      drift_items: ([.[] | select(.status == "drift")] | sort_by(.age_days) | reverse),
      satisfied_items: ([.[] | select(.status == "satisfied")] | sort_by(.age_days) | reverse | .[0:10]),
      recent_pending: ([.[] | select(.status == "recent-pending")] | sort_by(.age_days) | reverse | .[0:20]),
      non_task_samples: ([.[] | select(.status == "non-task-class")] | .[0:10])
    }' "$tmp_final" > "$OUTPUT_PATH"

  echo "[mine] wrote: $OUTPUT_PATH"
  echo "[mine] summary: drift=$n_drift satisfied=$n_satisfied recent=$n_recent non_task=$n_nontask"
}

# ---- entry point -----------------------------------------------------------
if [[ $SELF_TEST -eq 1 ]]; then
  run_self_test
  exit $?
fi

do_scan
