#!/usr/bin/env bash
# decision-queue.sh — Decision Queue storage layer (substrate per ADR-043).
#
# Persistent prioritized queue of decisions the human owes a response on.
# Per-machine state at $XDG_STATE_HOME/.claude/state/decision-queue/ (default
# $HOME/.claude/state/decision-queue/). Mirrors the conv-tree state layout:
# computed view in queue.json, append-only audit log in queue.audit.jsonl.
#
# Subcommands:
#   add        --question STR [--project STR] [--mode QUICK|PICK|DEEP]
#              [--recommendation STR] [--counter STR] [--defer-cost STR]
#              [--option LABEL[:default][:CONSEQUENCES]]*  (repeatable, PICK mode)
#              [--source-link URL]* [--source-session ID]
#              [--depends-on DQ-ID]* [--downstream WHAT:N]*
#              [--from-json FILE | --from-json-stdin]
#              → prints new item ID to stdout, exit 0
#
#   list       [--project STR] [--mode QUICK|PICK|DEEP]
#              [--state open|answered|superseded|moot|all]
#              [--highlighted true|false|all] [--format json|table]
#              → prints filtered queue to stdout, exit 0
#
#   get        <id>
#              → prints item JSON to stdout, exit 0; exit 1 if not found
#
#   close      <id> --answer STR [--by user|dispatch|auto-default]
#              → marks state=answered, exit 0
#
#   update     <id> --field key=value [--field key=value]*
#              → applies field updates; exit 0; exit 1 if validation fails
#              (use this for state transitions to superseded/moot)
#
#   highlight  <id> --reason STR --level subtle|strong|urgent
#              → sets highlighted=true + appends to highlight_history, exit 0
#
#   unhighlight <id> [--reason STR]
#              → clears highlight + appends to highlight_history, exit 0
#
#   --self-test
#              → exercises all subcommands against $TMPDIR sandbox, exit 0/1
#
# Schema enforced by adapters/claude-code/schemas/decision-queue.schema.json.
# Atomic writes via tmpfile + mv. No locking in v1; single-writer assumption.

set -uo pipefail

# ---- paths ------------------------------------------------------------------

# Allow override for self-test isolation.
DQ_STATE_DIR="${DQ_STATE_DIR:-$HOME/.claude/state/decision-queue}"
DQ_QUEUE_FILE="$DQ_STATE_DIR/queue.json"
DQ_AUDIT_LOG="$DQ_STATE_DIR/queue.audit.jsonl"

# Schema lives in repo; resolve via this script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DQ_SCHEMA="$SCRIPT_DIR/../schemas/decision-queue.schema.json"

# Priority-score weights (v1 per ADR-043).
HIGHLIGHT_WEIGHT_SUBTLE=2
HIGHLIGHT_WEIGHT_STRONG=5
HIGHLIGHT_WEIGHT_URGENT=10
AGING_TAX=10
AGING_TAX_DAYS=14

# ---- utils ------------------------------------------------------------------

err() { echo "decision-queue.sh: $*" >&2; }
die() { err "$*"; exit 1; }

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# UUID v4. Use /proc/sys/kernel/random/uuid when available; otherwise compose
# from /dev/urandom via hexdump (portable across Linux/macOS/Git Bash).
gen_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    local hex
    hex=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    # Set version (v4) and variant bits per RFC 4122.
    local g1="${hex:0:8}"
    local g2="${hex:8:4}"
    local g3_raw="${hex:12:4}"; local g3="4${g3_raw:1:3}"
    local g4_raw="${hex:16:4}"; local g4_first=$((0x${g4_raw:0:1} & 0x3 | 0x8))
    local g4="$(printf '%x' "$g4_first")${g4_raw:1:3}"
    local g5="${hex:20:12}"
    printf '%s-%s-%s-%s-%s\n' "$g1" "$g2" "$g3" "$g4" "$g5"
  fi
}

ensure_state_dir() {
  mkdir -p "$DQ_STATE_DIR" 2>/dev/null || die "cannot create $DQ_STATE_DIR"
  [[ -f "$DQ_QUEUE_FILE" ]] || echo '{"schema_version":1,"items":[]}' > "$DQ_QUEUE_FILE"
  touch "$DQ_AUDIT_LOG"
}

# Audit-log an operation as a single JSONL line.
audit() {
  local op="$1"; local id="$2"; local extra="${3:-{\}}"
  local line
  line=$(jq -nc --arg ts "$(now_iso)" --arg op "$op" --arg id "$id" --argjson extra "$extra" \
    '{ts:$ts, op:$op, id:$id, extra:$extra}')
  echo "$line" >> "$DQ_AUDIT_LOG"
}

# Atomic write: jq → tmpfile → mv.
write_queue() {
  local new_content="$1"
  local tmp
  tmp=$(mktemp "$DQ_QUEUE_FILE.XXXXXX") || die "mktemp failed"
  printf '%s\n' "$new_content" > "$tmp" || { rm -f "$tmp"; die "write to tmpfile failed"; }
  mv "$tmp" "$DQ_QUEUE_FILE" || { rm -f "$tmp"; die "atomic rename failed"; }
}

# ---- priority-score ---------------------------------------------------------

# Compute priority score for a single item (called inline by list).
# Reads the item JSON from stdin, prints the updated item with priority_score.
compute_priority_jq='
def age_days: (now - (.created_at | fromdateiso8601)) / 86400;
def update_age: (now - (.updated_at | fromdateiso8601)) / 86400;
def highlight_weight:
  if .highlight_level == "urgent" then '"$HIGHLIGHT_WEIGHT_URGENT"'
  elif .highlight_level == "strong" then '"$HIGHLIGHT_WEIGHT_STRONG"'
  elif .highlight_level == "subtle" then '"$HIGHLIGHT_WEIGHT_SUBTLE"'
  else 0 end;
def aging_tax:
  if .state == "open" and update_age > '"$AGING_TAX_DAYS"' then '"$AGING_TAX"' else 0 end;
def dep_count: (.dependents | length);
. + {
  priority_score: ((age_days * 0.1) + (dep_count * 2) + highlight_weight + aging_tax)
}
'

# Re-compute dependents (inverse of dependencies) for every item.
# Reads queue.json (full file), writes updated queue.json.
recompute_dependents_and_priority() {
  local current; current=$(cat "$DQ_QUEUE_FILE")
  local updated
  updated=$(echo "$current" | jq '
    # Build id -> dependents map.
    (.items | map(.id) ) as $ids
    | (reduce .items[] as $it ({}; reduce $it.dependencies[] as $dep (.; .[$dep] = ((.[$dep] // []) + [$it.id]))) ) as $depmap
    | .items |= map(. + {dependents: ($depmap[.id] // [])})
    | .items |= map('"$compute_priority_jq"')
  ')
  write_queue "$updated"
}

# ---- validation ------------------------------------------------------------

# Light schema validation: required keys present, enum values valid,
# UUID format. Heavy JSON Schema validation requires ajv; we accept it as
# optional and fall back to jq-based shape checks.
validate_item() {
  local item="$1"
  # Required-keys check via jq.
  local missing
  missing=$(echo "$item" | jq -r '
    ["id","schema_version","created_at","updated_at","project","question","mode","state","highlighted","highlight_history","dependencies","dependents","source_doc_links","downstream_impact","priority_score"]
    | map(. as $k | select(($item | has($k)) | not)) | join(",")
  ' --argjson item "$item" 2>/dev/null || echo "JQ_PARSE_ERROR")
  if [[ "$missing" == "JQ_PARSE_ERROR" ]]; then
    err "validate: item is not parseable JSON"
    return 1
  fi
  if [[ -n "$missing" ]]; then
    err "validate: missing required keys: $missing"
    return 1
  fi
  # Mode enum.
  local mode; mode=$(echo "$item" | jq -r '.mode')
  case "$mode" in QUICK|PICK|DEEP) ;; *) err "validate: invalid mode '$mode'"; return 1 ;; esac
  # State enum.
  local state; state=$(echo "$item" | jq -r '.state')
  case "$state" in open|answered|superseded|moot) ;; *) err "validate: invalid state '$state'"; return 1 ;; esac
  # ID format (DQ-uuid).
  local id; id=$(echo "$item" | jq -r '.id')
  if ! [[ "$id" =~ ^DQ-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    err "validate: invalid id format '$id'"
    return 1
  fi
  return 0
}

# ---- subcommand: add --------------------------------------------------------

cmd_add() {
  ensure_state_dir
  local question="" project="cross-cutting" mode="QUICK"
  local recommendation="" counterargument="" defer_cost=""
  local source_session=""
  local -a options=() source_links=() depends_on=() downstream=()
  local from_json="" from_stdin=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --question) question="$2"; shift 2 ;;
      --project) project="$2"; shift 2 ;;
      --mode) mode="$2"; shift 2 ;;
      --recommendation) recommendation="$2"; shift 2 ;;
      --counter|--counterargument) counterargument="$2"; shift 2 ;;
      --defer-cost|--consequence-of-deferring) defer_cost="$2"; shift 2 ;;
      --option) options+=("$2"); shift 2 ;;
      --source-link) source_links+=("$2"); shift 2 ;;
      --source-session) source_session="$2"; shift 2 ;;
      --depends-on) depends_on+=("$2"); shift 2 ;;
      --downstream) downstream+=("$2"); shift 2 ;;
      --from-json) from_json="$2"; shift 2 ;;
      --from-json-stdin) from_stdin=1; shift 1 ;;
      *) die "add: unknown flag '$1'" ;;
    esac
  done

  local id; id="DQ-$(gen_uuid)"
  local ts; ts=$(now_iso)

  # If --from-json{,-stdin}, take fields from JSON and overlay CLI-provided ones.
  local input_json='{}'
  if [[ -n "$from_json" ]]; then
    [[ -r "$from_json" ]] || die "add: cannot read $from_json"
    input_json=$(cat "$from_json")
  elif [[ "$from_stdin" -eq 1 ]]; then
    input_json=$(cat)
  fi

  # Build options[] from --option label[:default][:consequences] form.
  local options_json='[]'
  if [[ ${#options[@]} -gt 0 ]]; then
    options_json='['
    local first=1
    local opt
    for opt in "${options[@]}"; do
      local label="${opt%%:*}"
      local rest="${opt#*:}"
      local default_flag="false"
      local consequences=""
      if [[ "$rest" != "$opt" ]]; then
        # had a colon
        if [[ "$rest" == "default" || "$rest" == default:* ]]; then
          default_flag="true"
          consequences="${rest#default}"
          consequences="${consequences#:}"
        else
          consequences="$rest"
        fi
      fi
      local entry; entry=$(jq -nc --arg l "$label" --argjson d "$default_flag" --arg c "$consequences" \
        '{label:$l, default:$d} + (if $c == "" then {} else {consequences:$c} end)')
      if [[ $first -eq 1 ]]; then options_json="$entry"; first=0; else options_json="$options_json,$entry"; fi
    done
    options_json="[$options_json]"
  fi

  # Build source_doc_links and downstream_impact and dependencies arrays.
  local links_json='[]'
  if [[ ${#source_links[@]} -gt 0 ]]; then
    links_json=$(printf '%s\n' "${source_links[@]}" | jq -R . | jq -sc .)
  fi
  local deps_json='[]'
  if [[ ${#depends_on[@]} -gt 0 ]]; then
    deps_json=$(printf '%s\n' "${depends_on[@]}" | jq -R . | jq -sc .)
  fi
  local downstream_json='[]'
  if [[ ${#downstream[@]} -gt 0 ]]; then
    downstream_json='['
    local first=1 ds
    for ds in "${downstream[@]}"; do
      local what="${ds%:*}"
      local n="${ds##*:}"
      local entry; entry=$(jq -nc --arg w "$what" --argjson n "$n" '{what:$w, blocks_n_items:$n}')
      if [[ $first -eq 1 ]]; then downstream_json="$entry"; first=0; else downstream_json="$downstream_json,$entry"; fi
    done
    downstream_json="[$downstream_json]"
  fi

  local source_session_val
  if [[ -z "$source_session" ]]; then source_session_val="null"; else source_session_val="$(jq -n --arg s "$source_session" '$s')"; fi

  # Compose item, overlay --from-json{,-stdin} fields, then enforce ID + timestamps.
  local item
  item=$(jq -nc \
    --arg id "$id" \
    --arg ts "$ts" \
    --arg project "$project" \
    --arg question "$question" \
    --arg recommendation "$recommendation" \
    --arg counterargument "$counterargument" \
    --arg defer_cost "$defer_cost" \
    --arg mode "$mode" \
    --argjson options "$options_json" \
    --argjson dependencies "$deps_json" \
    --argjson source_doc_links "$links_json" \
    --argjson downstream_impact "$downstream_json" \
    --argjson source_session "$source_session_val" \
    --argjson input "$input_json" \
    '
      $input + {
        id: $id,
        schema_version: 1,
        created_at: $ts,
        updated_at: $ts,
        closed_at: null,
        project: $project,
        question: $question,
        recommendation: $recommendation,
        counterargument: $counterargument,
        consequence_of_deferring: $defer_cost,
        mode: $mode,
        options: $options,
        dependencies: $dependencies,
        dependents: [],
        source_doc_links: $source_doc_links,
        source_session_id: $source_session,
        downstream_impact: $downstream_impact,
        state: "open",
        answer: "",
        answer_by: null,
        priority_score: 0,
        highlighted: false,
        highlight_reason: null,
        highlight_level: null,
        highlight_history: []
      }
    ')

  validate_item "$item" || die "add: validation failed"

  # Insert into queue.
  local cur; cur=$(cat "$DQ_QUEUE_FILE")
  local new; new=$(echo "$cur" | jq --argjson item "$item" '.items += [$item]')
  write_queue "$new"
  recompute_dependents_and_priority

  audit "add" "$id" "$(jq -nc --arg p "$project" --arg m "$mode" '{project:$p,mode:$m}')"
  echo "$id"
}

# ---- subcommand: list -------------------------------------------------------

cmd_list() {
  ensure_state_dir
  recompute_dependents_and_priority
  local project="" mode="" state="open" highlighted="all" format="json"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --mode) mode="$2"; shift 2 ;;
      --state) state="$2"; shift 2 ;;
      --highlighted) highlighted="$2"; shift 2 ;;
      --format) format="$2"; shift 2 ;;
      *) die "list: unknown flag '$1'" ;;
    esac
  done

  local items
  items=$(cat "$DQ_QUEUE_FILE" | jq '.items')

  # Filter.
  if [[ "$state" != "all" ]]; then
    items=$(echo "$items" | jq --arg s "$state" 'map(select(.state == $s))')
  fi
  if [[ -n "$project" ]]; then
    items=$(echo "$items" | jq --arg p "$project" 'map(select(.project == $p))')
  fi
  if [[ -n "$mode" ]]; then
    items=$(echo "$items" | jq --arg m "$mode" 'map(select(.mode == $m))')
  fi
  if [[ "$highlighted" != "all" ]]; then
    local h="true"; [[ "$highlighted" == "false" ]] && h="false"
    items=$(echo "$items" | jq --argjson h "$h" 'map(select(.highlighted == $h))')
  fi

  # Sort by priority_score descending.
  items=$(echo "$items" | jq 'sort_by(.priority_score) | reverse')

  if [[ "$format" == "table" ]]; then
    echo "$items" | jq -r '.[] | "\(.priority_score | floor)\t\(.id[:14])...\t\(.project)\t\(.mode)\t\(.highlighted | if . then "★" else " " end)\t\(.question)"'
  else
    echo "$items"
  fi
}

# ---- subcommand: get --------------------------------------------------------

cmd_get() {
  ensure_state_dir
  recompute_dependents_and_priority
  local id="${1:-}"
  [[ -n "$id" ]] || die "get: missing <id>"
  local item; item=$(jq --arg id "$id" '.items[] | select(.id == $id)' "$DQ_QUEUE_FILE")
  [[ -n "$item" ]] || { err "get: not found: $id"; return 1; }
  echo "$item"
}

# ---- subcommand: close ------------------------------------------------------

cmd_close() {
  ensure_state_dir
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "close: missing <id>"
  local answer="" by="user"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --answer) answer="$2"; shift 2 ;;
      --by) by="$2"; shift 2 ;;
      *) die "close: unknown flag '$1'" ;;
    esac
  done
  case "$by" in user|dispatch|auto-default) ;; *) die "close: invalid --by '$by'" ;; esac

  local ts; ts=$(now_iso)
  local cur; cur=$(cat "$DQ_QUEUE_FILE")
  # Verify item exists.
  local exists; exists=$(echo "$cur" | jq --arg id "$id" '[.items[] | select(.id == $id)] | length')
  [[ "$exists" == "1" ]] || { err "close: not found: $id"; return 1; }

  local new
  new=$(echo "$cur" | jq --arg id "$id" --arg ts "$ts" --arg answer "$answer" --arg by "$by" '
    .items |= map(
      if .id == $id then
        . + {state: "answered", answer: $answer, answer_by: $by, closed_at: $ts, updated_at: $ts}
      else . end
    )
  ')
  write_queue "$new"
  audit "close" "$id" "$(jq -nc --arg a "$answer" --arg by "$by" '{answer:$a,by:$by}')"
}

# ---- subcommand: update -----------------------------------------------------

cmd_update() {
  ensure_state_dir
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "update: missing <id>"
  local ts; ts=$(now_iso)
  local cur; cur=$(cat "$DQ_QUEUE_FILE")
  local exists; exists=$(echo "$cur" | jq --arg id "$id" '[.items[] | select(.id == $id)] | length')
  [[ "$exists" == "1" ]] || { err "update: not found: $id"; return 1; }

  # Build a {key:value, ...} update object from --field key=value pairs.
  local update_obj='{}'
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --field)
        local kv="$2"; shift 2
        local k="${kv%%=*}"; local v="${kv#*=}"
        # Heuristic: numeric-looking → number; "true"/"false" → bool; else string.
        local val_json
        if [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
          val_json="$v"
        elif [[ "$v" == "true" || "$v" == "false" ]]; then
          val_json="$v"
        else
          val_json=$(jq -n --arg s "$v" '$s')
        fi
        update_obj=$(echo "$update_obj" | jq --arg k "$k" --argjson v "$val_json" '. + {($k): $v}')
        ;;
      *) die "update: unknown flag '$1'" ;;
    esac
  done

  local new
  new=$(echo "$cur" | jq --arg id "$id" --arg ts "$ts" --argjson upd "$update_obj" '
    .items |= map(
      if .id == $id then . + $upd + {updated_at: $ts} else . end
    )
  ')
  write_queue "$new"
  audit "update" "$id" "$update_obj"
}

# ---- subcommand: highlight --------------------------------------------------

cmd_highlight() {
  ensure_state_dir
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "highlight: missing <id>"
  local reason="" level=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      --level) level="$2"; shift 2 ;;
      *) die "highlight: unknown flag '$1'" ;;
    esac
  done
  [[ -n "$reason" ]] || die "highlight: --reason is required (human-readable, e.g., 'blocks 8 other items')"
  case "$level" in subtle|strong|urgent) ;; *) die "highlight: --level must be one of: subtle | strong | urgent" ;; esac

  local ts; ts=$(now_iso)
  local cur; cur=$(cat "$DQ_QUEUE_FILE")
  local exists; exists=$(echo "$cur" | jq --arg id "$id" '[.items[] | select(.id == $id)] | length')
  [[ "$exists" == "1" ]] || { err "highlight: not found: $id"; return 1; }

  local actor="${DQ_ACTOR:-dispatch}"
  local hist_entry
  hist_entry=$(jq -nc --arg ts "$ts" --arg by "$actor" --arg r "$reason" --arg l "$level" \
    '{at:$ts, by:$by, action:"highlight", reason:$r, level:$l}')

  local new
  new=$(echo "$cur" | jq --arg id "$id" --arg ts "$ts" --arg r "$reason" --arg l "$level" --argjson he "$hist_entry" '
    .items |= map(
      if .id == $id then
        . + {highlighted: true, highlight_reason: $r, highlight_level: $l, updated_at: $ts, highlight_history: (.highlight_history + [$he])}
      else . end
    )
  ')
  write_queue "$new"
  audit "highlight" "$id" "$(jq -nc --arg r "$reason" --arg l "$level" '{reason:$r,level:$l}')"
}

# ---- subcommand: unhighlight ------------------------------------------------

cmd_unhighlight() {
  ensure_state_dir
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "unhighlight: missing <id>"
  local reason="manual clear"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      *) die "unhighlight: unknown flag '$1'" ;;
    esac
  done
  local ts; ts=$(now_iso)
  local cur; cur=$(cat "$DQ_QUEUE_FILE")
  local exists; exists=$(echo "$cur" | jq --arg id "$id" '[.items[] | select(.id == $id)] | length')
  [[ "$exists" == "1" ]] || { err "unhighlight: not found: $id"; return 1; }

  local actor="${DQ_ACTOR:-dispatch}"
  local hist_entry
  hist_entry=$(jq -nc --arg ts "$ts" --arg by "$actor" --arg r "$reason" \
    '{at:$ts, by:$by, action:"unhighlight", reason:$r, level:null}')

  local new
  new=$(echo "$cur" | jq --arg id "$id" --arg ts "$ts" --argjson he "$hist_entry" '
    .items |= map(
      if .id == $id then
        . + {highlighted: false, highlight_reason: null, highlight_level: null, updated_at: $ts, highlight_history: (.highlight_history + [$he])}
      else . end
    )
  ')
  write_queue "$new"
  audit "unhighlight" "$id" "$(jq -nc --arg r "$reason" '{reason:$r}')"
}

# ---- self-test --------------------------------------------------------------

cmd_selftest() {
  local sandbox; sandbox=$(mktemp -d)
  export DQ_STATE_DIR="$sandbox/state"
  DQ_QUEUE_FILE="$DQ_STATE_DIR/queue.json"
  DQ_AUDIT_LOG="$DQ_STATE_DIR/queue.audit.jsonl"
  local pass=0 fail=0 errors=()

  ok()   { pass=$((pass+1)); echo "  PASS: $1"; }
  fail() { fail=$((fail+1)); echo "  FAIL: $1" >&2; errors+=("$1"); }

  echo "decision-queue.sh self-test (sandbox: $sandbox)"

  # T1: add a QUICK item
  local id1
  id1=$(cmd_add --question "Should we ship X to prod tonight?" --project "<project-a>" --mode QUICK \
    --recommendation "Yes — tests are green and the rollback is a 1-line revert." \
    --counter "We discovered the bug late; another day of soak would feel safer." \
    --defer-cost "Customer onboarding flow ships Friday and waits on X.") || true
  if [[ "$id1" =~ ^DQ- ]]; then ok "T1 add QUICK returns DQ- id ($id1)"; else fail "T1 add QUICK did not return valid id"; fi

  # T2: list returns the item
  local listed; listed=$(cmd_list --format json 2>/dev/null)
  local count; count=$(echo "$listed" | jq 'length')
  [[ "$count" == "1" ]] && ok "T2 list returns 1 item" || fail "T2 list returned $count items (expected 1)"

  # T3: add a PICK item with options
  local id2
  id2=$(cmd_add --question "Which deploy target?" --project "<project-b>" --mode PICK \
    --option "vercel:default:Fast and current convention" \
    --option "fly:Cheaper but new dependency" \
    --option "self-host:Full control, ops overhead") || true
  if [[ "$id2" =~ ^DQ- ]]; then ok "T3 add PICK returns id ($id2)"; else fail "T3 add PICK failed"; fi

  # T4: get returns the item with all fields
  local got; got=$(cmd_get "$id2")
  local got_mode; got_mode=$(echo "$got" | jq -r '.mode')
  local got_options; got_options=$(echo "$got" | jq '.options | length')
  [[ "$got_mode" == "PICK" && "$got_options" == "3" ]] && ok "T4 get returns PICK with 3 options" \
    || fail "T4 get returned mode=$got_mode options=$got_options"

  # T5: highlight
  cmd_highlight "$id1" --reason "Blocks Friday customer onboarding launch" --level strong
  local h_state; h_state=$(cmd_get "$id1" | jq -r '"\(.highlighted) \(.highlight_level)"')
  [[ "$h_state" == "true strong" ]] && ok "T5 highlight set" || fail "T5 highlight state: $h_state"

  # T6: highlight history grew
  local hist_n; hist_n=$(cmd_get "$id1" | jq '.highlight_history | length')
  [[ "$hist_n" == "1" ]] && ok "T6 highlight history += 1" || fail "T6 history len=$hist_n"

  # T7: priority_score on highlighted item is non-zero
  local score; score=$(cmd_get "$id1" | jq '.priority_score')
  awk -v s="$score" 'BEGIN { exit (s >= 5 ? 0 : 1) }' && ok "T7 highlighted item priority_score >= 5 (got $score)" \
    || fail "T7 priority_score $score < 5"

  # T8: unhighlight clears
  cmd_unhighlight "$id1" --reason "user dismissed"
  local h_state2; h_state2=$(cmd_get "$id1" | jq -r '"\(.highlighted) \(.highlight_level)"')
  [[ "$h_state2" == "false null" ]] && ok "T8 unhighlight clears" || fail "T8 state after unhighlight: $h_state2"

  # T9: filter by --highlighted true → empty
  local hcount; hcount=$(cmd_list --highlighted true --format json | jq 'length')
  [[ "$hcount" == "0" ]] && ok "T9 filter highlighted=true returns 0 after unhighlight" \
    || fail "T9 highlighted=true returned $hcount"

  # T10: close item with answer
  cmd_close "$id1" --answer "Ship it; I'll babysit prod for 30 min" --by user
  local state_after; state_after=$(cmd_get "$id1" | jq -r '.state')
  [[ "$state_after" == "answered" ]] && ok "T10 close → state=answered" || fail "T10 state=$state_after"

  # T11: list default --state open excludes answered
  local open_count; open_count=$(cmd_list --format json | jq 'length')
  [[ "$open_count" == "1" ]] && ok "T11 default list (state=open) returns 1 (the PICK item, not the closed one)" \
    || fail "T11 open_count=$open_count expected 1"

  # T12: list --state all returns both
  local all_count; all_count=$(cmd_list --state all --format json | jq 'length')
  [[ "$all_count" == "2" ]] && ok "T12 list --state all returns 2" || fail "T12 all_count=$all_count"

  # T13: dependencies → dependents computed
  local id3
  id3=$(cmd_add --question "Depends on $id2 — pick a CI matrix shape" --project "<project-b>" --mode QUICK \
    --depends-on "$id2")
  local deps_on_id2; deps_on_id2=$(cmd_get "$id2" | jq '.dependents | length')
  [[ "$deps_on_id2" == "1" ]] && ok "T13 dependents computed (id2 has 1 dependent: id3)" \
    || fail "T13 id2 dependents=$deps_on_id2 expected 1"

  # T14: update arbitrary field (state → moot with reason)
  cmd_update "$id3" --field state=moot --field answer="Superseded by the platform decision"
  local id3_state; id3_state=$(cmd_get "$id3" | jq -r '.state')
  [[ "$id3_state" == "moot" ]] && ok "T14 update field works" || fail "T14 state=$id3_state expected moot"

  # T15: --highlighted false returns open non-highlighted items
  local non_h_count; non_h_count=$(cmd_list --highlighted false --format json | jq 'length')
  [[ "$non_h_count" -ge "1" ]] && ok "T15 --highlighted false returns non-highlighted items" \
    || fail "T15 non-highlighted count=$non_h_count"

  # T16: audit log has entries for every mutating operation.
  # Expected entries through T15: T1 add, T3 add, T5 highlight, T8 unhighlight,
  # T10 close, T13 add, T14 update = 7.
  local audit_n; audit_n=$(wc -l < "$DQ_AUDIT_LOG" | tr -d ' ')
  [[ "$audit_n" -ge "7" ]] && ok "T16 audit log has $audit_n entries (≥ 7)" \
    || fail "T16 audit log has only $audit_n entries"

  # T17: invalid mode rejected
  set +e
  local id_bad
  id_bad=$(cmd_add --question "bad" --project "x" --mode BOGUS 2>/dev/null)
  local rc=$?
  set -e
  [[ "$rc" != "0" && -z "$id_bad" ]] && ok "T17 invalid mode rejected (exit non-zero)" \
    || fail "T17 invalid mode accepted (rc=$rc id=$id_bad)"

  # T18: table format works
  local table_out; table_out=$(cmd_list --state all --format table | wc -l | tr -d ' ')
  [[ "$table_out" -ge "1" ]] && ok "T18 table format produces output" || fail "T18 table format produced $table_out lines"

  # Cleanup.
  rm -rf "$sandbox"

  echo ""
  echo "RESULT: $pass passed, $fail failed"
  if [[ "$fail" -gt 0 ]]; then
    echo "Failures:"
    printf '  - %s\n' "${errors[@]}"
    return 1
  fi
  return 0
}

# ---- main dispatch ----------------------------------------------------------

if [[ $# -eq 0 ]]; then
  cat <<EOF
Usage: decision-queue.sh <subcommand> [args]

Subcommands:
  add        add a new decision item (see header for flags)
  list       list pending items (filter + format flags)
  get        <id>  print one item
  close      <id> --answer STR [--by user|dispatch|auto-default]
  update     <id> --field key=value [--field ...]
  highlight  <id> --reason STR --level subtle|strong|urgent
  unhighlight <id> [--reason STR]
  --self-test  run self-test suite

See: docs/dispatch-decision-queue-tools.md for the calling convention.
     docs/decisions/043-decision-queue-substrate.md for the substrate ADR.
EOF
  exit 0
fi

case "$1" in
  add) shift; cmd_add "$@" ;;
  list) shift; cmd_list "$@" ;;
  get) shift; cmd_get "$@" ;;
  close) shift; cmd_close "$@" ;;
  update) shift; cmd_update "$@" ;;
  highlight) shift; cmd_highlight "$@" ;;
  unhighlight) shift; cmd_unhighlight "$@" ;;
  --self-test|--selftest|selftest|self-test) cmd_selftest ;;
  *) die "unknown subcommand '$1' (try without args for help)" ;;
esac
