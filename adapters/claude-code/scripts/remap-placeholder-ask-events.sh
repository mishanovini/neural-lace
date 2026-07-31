#!/bin/bash
# remap-placeholder-ask-events.sh — ONE-SHOT, IDEMPOTENT historical-data
# repair for the proven 2026-07-27 progress-log emitter bug.
#
# ============================================================
# THE BUG (full story: hooks/lib/progress-log-lib.sh's
# _pl_is_placeholder_ask_id header comment; hooks/plan-lifecycle.sh's
# extract_ask_id header comment)
# ============================================================
#
# adapters/claude-code/templates/plan-template.md's own header default is
# the LITERAL `ask-id: <id | none — no linked ask>`. A plan file that never
# ran through start-plan.sh's `--ask-id` substitution (hand-copied from the
# template, or created before that substitution existed) keeps that literal
# text. plan-lifecycle.sh's `extract_ask_id` and workstreams-emit.sh's
# `_resolve_ask_id_for_plan_slug` both used to parse that header with a
# pattern that matched the leftover text and handed pl_emit the truncated
# literal token `<id` as if it were a real ask-id. pl_path_for's sanitizer
# then mapped the lone `<` to `_`, producing the plausible-but-wrong file
# `_id.jsonl` — 1090 real task_started/task_done/merged events, proven on
# this machine, for 4 real plans (cockpit-roadmap-redesign,
# cockpit-v2-push-materialized-store, evidence-bar-enforcement,
# cockpit-ui-polish), every one invisible to workstreams-ui/server/
# roadmap-routes.js's eventsForSlug per-ask lookup.
#
# The EMITTER is fixed at the source (both extractors above) AND at the
# writer (progress-log-lib.sh's pl_path_for quarantines any FUTURE
# placeholder-shaped ask_id to unattributed.jsonl). This script repairs the
# EXISTING damage: every event already sitting in `_id.jsonl` needs to move
# to the file it would have landed in had the bug never existed.
#
# ============================================================
# THE REPAIR — mechanical, not a guess
# ============================================================
#
# Every event in _id.jsonl already carries its own `plan_slug` field (the
# bug never touched plan_slug — only ask_id). For each event this script:
#   1. Reads plan_slug from the event.
#   2. Locates that plan's CURRENT file (docs/plans/<slug>.md, or
#      docs/plans/archive/<slug>.md, or docs/plans/deferred/<slug>.md —
#      plan-lifecycle.sh's own archival destinations, since 3 of the 4
#      known-affected plans have since been archived).
#   3. Re-derives the plan's REAL ask-id with the SAME (now-fixed)
#      extraction logic plan-lifecycle.sh's extract_ask_id uses.
#   4. Appends the event, byte-for-byte UNCHANGED, to the correct
#      destination file (the real ask-id's log, or "unlinked.jsonl" if the
#      plan genuinely has none) — deduped against that destination's
#      existing event_ids (pl_emit's own convention), so a second run is a
#      safe no-op even before the completion marker below is checked.
#   5. A plan_slug that cannot be resolved to any file on disk falls back
#      to "unlinked.jsonl" too (the same honest default pl_path_for("")
#      uses) — never silently dropped.
#
# NEVER rewrites _id.jsonl in place, NEVER deletes it. After a successful
# run the ORIGINAL file is renamed (not overwritten) to
# "_id.jsonl.migrated-<UTC-ts>" — every original byte survives under a new
# name — and a small JSON receipt is written to "_id.jsonl.migrated" (counts
# + timestamp + backup path). A second invocation sees that receipt and
# no-ops immediately (idempotent) instead of re-scanning.
#
# ============================================================
# USAGE
# ============================================================
#   remap-placeholder-ask-events.sh [--dry-run]
#     --dry-run   report what WOULD move (per-destination counts), touch
#                 NOTHING on disk. Safe to run any number of times.
#   remap-placeholder-ask-events.sh --self-test
#     Self-contained assertion suite, entirely sandboxed under
#     PROGRESS_LOG_STATE_DIR / a synthetic docs/plans tree — never touches
#     the real machine's state.
#
# ============================================================
# SANDBOXING / REPO-ROOT RESOLUTION
# ============================================================
#   - Progress-log state dir: delegated to hooks/lib/progress-log-lib.sh's
#     pl_state_dir (PROGRESS_LOG_STATE_DIR env override, else
#     HARNESS_SELFTEST=1 sandbox, else the real $HOME/.claude/state/
#     progress-logs). One implementation, sourced — not re-derived here.
#   - Plan-file repo root: REMAP_REPO_ROOT env override (tests), else
#     `git rev-parse --show-toplevel` from cwd.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [[ -f "$SCRIPT_DIR/../hooks/lib/progress-log-lib.sh" ]]; then
  source "$SCRIPT_DIR/../hooks/lib/progress-log-lib.sh"
else
  echo "remap-placeholder-ask-events.sh: cannot find hooks/lib/progress-log-lib.sh next to scripts/ — aborting (no-op, never blocks a caller)" >&2
  exit 0
fi

# ----------------------------------------------------------------------
# _remap_json_field <line> <field> — best-effort single-field extraction
# from one flat progress-log JSON line. Prefers jq (available on this
# harness's dev machines); falls back to a sed extraction matched to
# _pl_json_escape's own escaping convention (every field is always present
# as a possibly-empty string — schemas/progress-log-event.schema.json).
# ----------------------------------------------------------------------
_remap_json_field() {
  local line="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$line" | jq -r --arg f "$field" '.[$f] // ""' 2>/dev/null && return 0
  fi
  printf '%s' "$line" | sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1
}

# ----------------------------------------------------------------------
# _remap_extract_ask_id_from_file <planfile> — the SAME fixed extraction
# hooks/plan-lifecycle.sh's extract_ask_id uses (deliberately duplicated —
# see that function's own header comment on why this harness keeps these
# copies independent rather than sourcing a hook from a script). A
# placeholder-shaped header value (starts with '<') resolves to empty, the
# same as a genuinely absent header.
# ----------------------------------------------------------------------
_remap_extract_ask_id_from_file() {
  local planfile="$1"
  [[ -f "$planfile" ]] || { printf ''; return 0; }
  local raw
  raw="$(awk '
    /^ask-id:[[:space:]]*[^[:space:]]+/ {
      sub(/^ask-id:[[:space:]]*/, "", $0)
      sub(/[[:space:]].*$/, "", $0)
      print $0
      exit
    }
  ' "$planfile" 2>/dev/null)"
  case "$raw" in
    # '<'* = template placeholder; none = the documented no-ask spelling —
    # both sentinels resolve to empty so remapped events land in the
    # UNLINKED lane, never none.jsonl (re-review Critical, 2026-07-28).
    '<'* | none) printf ''; return 0 ;;
  esac
  printf '%s' "$raw"
}

# ----------------------------------------------------------------------
# _remap_find_planfile <repo_root> <slug> — locate a plan file across the
# three destinations plan-lifecycle.sh's own archival logic uses: active
# docs/plans/, docs/plans/archive/ (COMPLETED), docs/plans/deferred/
# (DEFERRED). Empty when the slug resolves to none of the three.
# ----------------------------------------------------------------------
_remap_find_planfile() {
  local root="$1" slug="$2"
  [[ -z "$slug" ]] && { printf ''; return 0; }
  local cand
  for cand in "$root/docs/plans/$slug.md" "$root/docs/plans/archive/$slug.md" "$root/docs/plans/deferred/$slug.md"; do
    if [[ -f "$cand" ]]; then
      printf '%s' "$cand"
      return 0
    fi
  done
  printf ''
}

# ----------------------------------------------------------------------
# cmd_run [--dry-run] — the one-shot remap.
# ----------------------------------------------------------------------
cmd_run() {
  # --source <basename> (re-review 2026-07-28, Critical generalization):
  # the sentinel CLASS has two live instances — `_id.jsonl` (template
  # placeholder) and `none.jsonl` (the documented no-ask spelling, 141
  # live events) — the run path processes BOTH by default (see main).
  local dry_run=0 src_base="_id.jsonl"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=1 ;;
      --source) shift; src_base="${1:-_id.jsonl}" ;;
    esac
    shift
  done

  local state_dir src marker
  state_dir="$(pl_state_dir)"
  src="$state_dir/$src_base"
  marker="$src.migrated"

  if [[ -f "$marker" ]]; then
    # REBORN-SOURCE GUARD (re-review 2026-07-28, Major): if the source
    # exists AGAIN after a completed migration, a pre-fix emitter is
    # still live somewhere (deploy the fixed hooks first — the marker
    # must NEVER silently strand a reborn file's events). Loud warning,
    # nonzero exit; delete the marker to force reprocessing once the
    # fixed hooks are actually installed. ORDERING LAW: install the
    # fixed hooks live BEFORE the real remap run.
    if [[ -f "$src" ]]; then
      echo "remap-placeholder-ask-events.sh: WARNING — $src EXISTS AGAIN after a completed migration (a pre-fix emitter is still live; install the fixed hooks, then delete $marker to reprocess). Receipt of the earlier run:" >&2
      cat "$marker" >&2
      return 1
    fi
    echo "remap-placeholder-ask-events.sh: already migrated — receipt at $marker:"
    cat "$marker"
    return 0
  fi

  if [[ ! -f "$src" ]]; then
    echo "remap-placeholder-ask-events.sh: no $src found — nothing to remap."
    return 0
  fi

  local root
  root="${REMAP_REPO_ROOT:-}"
  if [[ -z "$root" ]]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  if [[ -z "$root" ]]; then
    echo "remap-placeholder-ask-events.sh: could not resolve a repo root (set REMAP_REPO_ROOT) — aborting, $src left untouched." >&2
    return 0
  fi

  # CONCURRENCY GUARD: a not-yet-fixed sibling session (a worktree that
  # hasn't merged this fix) could still be actively appending to $src while
  # this runs. Snapshot the line count now; compared against the count
  # again right before the rename below, so a concurrent append is
  # detected rather than silently lost under the source into the backup.
  local lines_before
  lines_before=$(wc -l < "$src" 2>/dev/null | tr -d ' ')

  local total=0 moved=0 skipped_dup=0
  declare -A dest_counts=()

  local line eid pslug planfile real_ask dest dest_file
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    total=$((total + 1))
    eid="$(_remap_json_field "$line" event_id)"
    pslug="$(_remap_json_field "$line" plan_slug)"

    real_ask=""
    if [[ -n "$pslug" ]]; then
      planfile="$(_remap_find_planfile "$root" "$pslug")"
      [[ -n "$planfile" ]] && real_ask="$(_remap_extract_ask_id_from_file "$planfile")"
    fi

    if [[ -n "$real_ask" ]]; then
      dest_file="$(pl_path_for "$real_ask")"
      dest="$(basename "$dest_file")"
    else
      dest_file="$state_dir/unlinked.jsonl"
      dest="unlinked.jsonl"
    fi

    if [[ "$dry_run" == "1" ]]; then
      dest_counts["$dest"]=$(( ${dest_counts["$dest"]:-0} + 1 ))
      continue
    fi

    if [[ -n "$eid" ]] && [[ -f "$dest_file" ]] && grep -qF "\"event_id\":\"$eid\"" "$dest_file" 2>/dev/null; then
      skipped_dup=$((skipped_dup + 1))
      continue
    fi
    mkdir -p "$(dirname "$dest_file")" 2>/dev/null || true
    printf '%s\n' "$line" >> "$dest_file"
    moved=$((moved + 1))
    dest_counts["$dest"]=$(( ${dest_counts["$dest"]:-0} + 1 ))
  done < "$src"

  if [[ "$dry_run" == "1" ]]; then
    echo "remap-placeholder-ask-events.sh --dry-run: $total event(s) in $src would move as follows (no changes made):"
    local d
    for d in "${!dest_counts[@]}"; do
      echo "  -> $d: ${dest_counts[$d]}"
    done
    return 0
  fi

  # CONCURRENCY GUARD (see snapshot above): if $src grew WHILE we were
  # reading it (a not-yet-fixed sibling session/worktree still appending
  # via the pre-fix extractor), do NOT rename it away — every line we DID
  # process is already safely (and idempotently, via the dedup check above)
  # copied to its correct destination, but renaming now would strand the
  # NEW lines nobody has processed yet inside a backup nothing ever reads
  # again. Leave $src in place, write NO completion marker, and say so: the
  # next invocation reprocesses the whole file, which is safe (every
  # already-migrated line dedups against its destination's existing
  # event_id; only the genuinely-new lines actually append).
  local lines_after
  lines_after=$(wc -l < "$src" 2>/dev/null | tr -d ' ')
  if [[ "$lines_after" != "$lines_before" ]]; then
    echo "remap-placeholder-ask-events.sh: $src grew while migrating ($lines_before -> $lines_after lines — a concurrent writer is still appending, likely an un-fixed sibling worktree). Migrated $moved of the original $total event(s) to their destinations (idempotent; already-safe). Left $src IN PLACE and wrote NO completion marker so the next run reprocesses it (safe: already-migrated lines dedup). Re-run this script once the concurrent writer's fix has landed." >&2
    return 0
  fi

  local ts backup
  ts="$(date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null || echo 'unknown')"
  backup="$src.migrated-$ts"
  mv "$src" "$backup" 2>/dev/null || { echo "remap-placeholder-ask-events.sh: WARNING — could not rename $src to $backup; events were still appended to their correct destinations, but the source file was left in place (re-running will re-check dedup, not double-count)." >&2; }

  {
    printf '{"migrated_ts":"%s","source_backup":"%s","total_events":%d,"moved":%d,"skipped_as_duplicate":%d,"destinations":{' \
      "$ts" "$backup" "$total" "$moved" "$skipped_dup"
    local first=1 d
    for d in "${!dest_counts[@]}"; do
      [[ "$first" == "1" ]] || printf ','
      first=0
      printf '"%s":%d' "$d" "${dest_counts[$d]}"
    done
    printf '}}\n'
  } > "$marker"

  echo "remap-placeholder-ask-events.sh: migrated $moved of $total event(s) ($skipped_dup already-duplicate) from $src"
  echo "  original backed up (unmodified) at: $backup"
  echo "  receipt: $marker"
  local d
  for d in "${!dest_counts[@]}"; do
    echo "  -> $d: ${dest_counts[$d]}"
  done
  return 0
}

# ============================================================
# --self-test (sandboxed: synthetic docs/plans tree + PROGRESS_LOG_STATE_DIR)
# ============================================================
cmd_selftest() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local TMP
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'remapst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi
  trap 'rm -rf "$TMP"' RETURN

  export HARNESS_SELFTEST=1
  export PROGRESS_LOG_STATE_DIR="$TMP/pl"
  mkdir -p "$PROGRESS_LOG_STATE_DIR"
  mkdir -p "$TMP/repo/docs/plans/archive" "$TMP/repo/docs/plans/deferred"
  export REMAP_REPO_ROOT="$TMP/repo"

  cat >"$TMP/repo/docs/plans/still-active.md" <<'EOP'
# Plan: Still active (placeholder never filled in)
Status: ACTIVE
ask-id: <id | none — no linked ask>
EOP
  cat >"$TMP/repo/docs/plans/archive/was-completed.md" <<'EOP'
# Plan: Was completed (placeholder never filled in, now archived)
Status: COMPLETED
ask-id: <id | none — no linked ask>
EOP
  cat >"$TMP/repo/docs/plans/archive/has-real-ask.md" <<'EOP'
# Plan: Has a real linked ask
Status: COMPLETED
ask-id: ask-real-123
EOP

  echo "Scenario A: 3 legacy events (2 placeholder-plan slugs + 1 unresolvable slug) all remap to unlinked.jsonl"
  cat >"$PROGRESS_LOG_STATE_DIR/_id.jsonl" <<EOP
{"v":1,"event_id":"evt-1","ts":"2026-07-14T00:00:00Z","ask_id":"<id","type":"task_done","plan_slug":"still-active","task_id":"1","sha":"sha1","needs_you_id":"","session_id":"","summary":"s1","evidence_link":"","emitter":"plan-lifecycle","provenance":"known","user":"u","machine":"m","repo":"r"}
{"v":1,"event_id":"evt-2","ts":"2026-07-14T00:01:00Z","ask_id":"<id","type":"merged","plan_slug":"was-completed","task_id":"","sha":"sha2","needs_you_id":"","session_id":"","summary":"s2","evidence_link":"","emitter":"auditor","provenance":"known","user":"u","machine":"m","repo":"r"}
{"v":1,"event_id":"evt-3","ts":"2026-07-14T00:02:00Z","ask_id":"<id","type":"task_started","plan_slug":"no-such-plan","task_id":"2","sha":"","needs_you_id":"","session_id":"sid3","summary":"s3","evidence_link":"","emitter":"workstreams-emit","provenance":"known","user":"u","machine":"m","repo":"r"}
EOP
  OUT_A="$(bash "$SCRIPT_DIR/remap-placeholder-ask-events.sh" 2>&1)"
  UNL="$PROGRESS_LOG_STATE_DIR/unlinked.jsonl"
  if [[ -f "$UNL" ]] && grep -qF '"event_id":"evt-1"' "$UNL" && grep -qF '"event_id":"evt-2"' "$UNL" && grep -qF '"event_id":"evt-3"' "$UNL"; then
    pass "all 3 legacy events (2 placeholder-plans + 1 unresolvable slug) landed in unlinked.jsonl"
  else
    fail "expected all 3 events in $UNL. Output was: $OUT_A"
  fi
  if [[ -f "$PROGRESS_LOG_STATE_DIR/_id.jsonl" ]]; then
    fail "_id.jsonl still present after a successful migration (should be renamed away)"
  else
    pass "_id.jsonl was renamed away (not deleted, not left in place)"
  fi
  if ls "$PROGRESS_LOG_STATE_DIR"/_id.jsonl.migrated-* >/dev/null 2>&1; then
    pass "an unmodified timestamped backup of the original _id.jsonl exists"
  else
    fail "no _id.jsonl.migrated-<ts> backup found"
  fi
  if [[ -f "$PROGRESS_LOG_STATE_DIR/_id.jsonl.migrated" ]] && command -v jq >/dev/null 2>&1 && jq -e . "$PROGRESS_LOG_STATE_DIR/_id.jsonl.migrated" >/dev/null 2>&1; then
    pass "a valid JSON receipt marker was written"
  else
    fail "no valid JSON receipt marker at _id.jsonl.migrated"
  fi

  echo "Scenario B: a plan_slug WITH a genuinely real linked ask-id remaps to THAT ask's own file, not unlinked"
  cat >"$PROGRESS_LOG_STATE_DIR/_id.jsonl" <<EOP
{"v":1,"event_id":"evt-4","ts":"2026-07-14T00:03:00Z","ask_id":"<id","type":"merged","plan_slug":"has-real-ask","task_id":"","sha":"sha4","needs_you_id":"","session_id":"","summary":"s4","evidence_link":"","emitter":"auditor","provenance":"known","user":"u","machine":"m","repo":"r"}
EOP
  rm -f "$PROGRESS_LOG_STATE_DIR/_id.jsonl.migrated" "$PROGRESS_LOG_STATE_DIR"/_id.jsonl.migrated-* 2>/dev/null
  bash "$SCRIPT_DIR/remap-placeholder-ask-events.sh" >/dev/null 2>&1
  if [[ -f "$PROGRESS_LOG_STATE_DIR/ask-real-123.jsonl" ]] && grep -qF '"event_id":"evt-4"' "$PROGRESS_LOG_STATE_DIR/ask-real-123.jsonl"; then
    pass "an event whose plan now has a real ask-id was re-homed to that ask's own file"
  else
    fail "expected evt-4 in $PROGRESS_LOG_STATE_DIR/ask-real-123.jsonl"
  fi

  echo "Scenario C: idempotent — a second invocation after migration is a safe no-op (does not re-append, does not error)"
  local before_lines after_lines
  before_lines=$(wc -l < "$PROGRESS_LOG_STATE_DIR/ask-real-123.jsonl" 2>/dev/null | tr -d ' ')
  OUT_C="$(bash "$SCRIPT_DIR/remap-placeholder-ask-events.sh" 2>&1)"
  after_lines=$(wc -l < "$PROGRESS_LOG_STATE_DIR/ask-real-123.jsonl" 2>/dev/null | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]] && printf '%s' "$OUT_C" | grep -qi "already migrated"; then
    pass "re-running after migration reports already-migrated and makes no further changes"
  else
    fail "second run was not a clean no-op (before=$before_lines after=$after_lines); output: $OUT_C"
  fi

  echo "Scenario D: --dry-run makes no changes at all"
  rm -f "$PROGRESS_LOG_STATE_DIR/_id.jsonl.migrated" "$PROGRESS_LOG_STATE_DIR"/_id.jsonl.migrated-* 2>/dev/null
  cat >"$PROGRESS_LOG_STATE_DIR/_id.jsonl" <<EOP
{"v":1,"event_id":"evt-5","ts":"2026-07-14T00:04:00Z","ask_id":"<id","type":"task_done","plan_slug":"still-active","task_id":"9","sha":"sha5","needs_you_id":"","session_id":"","summary":"s5","evidence_link":"","emitter":"plan-lifecycle","provenance":"known","user":"u","machine":"m","repo":"r"}
EOP
  OUT_D="$(bash "$SCRIPT_DIR/remap-placeholder-ask-events.sh" --dry-run 2>&1)"
  if [[ -f "$PROGRESS_LOG_STATE_DIR/_id.jsonl" ]] && ! grep -qF '"event_id":"evt-5"' "$UNL" 2>/dev/null && printf '%s' "$OUT_D" | grep -q "would move"; then
    pass "--dry-run reported the projected move and left _id.jsonl untouched"
  else
    fail "--dry-run should not have modified any file; output: $OUT_D"
  fi
  rm -f "$PROGRESS_LOG_STATE_DIR/_id.jsonl"

  echo "Scenario E: no _id.jsonl at all -> clean no-op, no error"
  rm -f "$PROGRESS_LOG_STATE_DIR/_id.jsonl.migrated" "$PROGRESS_LOG_STATE_DIR"/_id.jsonl.migrated-* 2>/dev/null
  OUT_E="$(bash "$SCRIPT_DIR/remap-placeholder-ask-events.sh" 2>&1)"
  if printf '%s' "$OUT_E" | grep -qi "nothing to remap"; then
    pass "absent _id.jsonl reports nothing-to-remap and exits cleanly"
  else
    fail "expected a nothing-to-remap message; got: $OUT_E"
  fi

  echo "Scenario F: a plan whose header is the documented no-ask spelling ('ask-id: none — ...') routes its events to unlinked.jsonl — 'none' is a sentinel, NEVER a real ask-id (re-review 2026-07-28)"
  cat >"$TMP/repo/docs/plans/none-header.md" <<'EOP'
# Plan: Cleaned header using the documented no-ask spelling
Status: ACTIVE
ask-id: none — no linked ask (was the literal template placeholder)
EOP
  rm -f "$PROGRESS_LOG_STATE_DIR/_id.jsonl.migrated" "$PROGRESS_LOG_STATE_DIR"/_id.jsonl.migrated-* 2>/dev/null
  cat >"$PROGRESS_LOG_STATE_DIR/_id.jsonl" <<EOP
{"v":1,"event_id":"evt-6","ts":"2026-07-14T00:05:00Z","ask_id":"<id","type":"task_done","plan_slug":"none-header","task_id":"1","sha":"sha6","needs_you_id":"","session_id":"","summary":"s6","evidence_link":"","emitter":"plan-lifecycle","provenance":"known","user":"u","machine":"m","repo":"r"}
EOP
  bash "$SCRIPT_DIR/remap-placeholder-ask-events.sh" >/dev/null 2>&1
  if grep -qF '"event_id":"evt-6"' "$UNL" 2>/dev/null; then
    pass "a 'none —' header plan's event landed in unlinked.jsonl (extractor resolved the sentinel to empty)"
  else
    fail "expected evt-6 in $UNL (the 'none' sentinel must not resolve as a real ask-id)"
  fi
  if [[ ! -f "$PROGRESS_LOG_STATE_DIR/none.jsonl" ]]; then
    pass "no none.jsonl was created by the remap (the sentinel never becomes a destination file)"
  else
    fail "none.jsonl was created — the 'none' spelling leaked through as a real ask-id"
  fi

  echo "Scenario G: the default run ALSO drains none.jsonl (dual-source) — events misfiled under the sanitized 'none' name are re-homed by plan_slug"
  rm -f "$PROGRESS_LOG_STATE_DIR"/_id.jsonl.migrated "$PROGRESS_LOG_STATE_DIR"/_id.jsonl.migrated-* \
        "$PROGRESS_LOG_STATE_DIR"/none.jsonl.migrated "$PROGRESS_LOG_STATE_DIR"/none.jsonl.migrated-* 2>/dev/null
  cat >"$PROGRESS_LOG_STATE_DIR/none.jsonl" <<EOP
{"v":1,"event_id":"evt-7","ts":"2026-07-14T00:06:00Z","ask_id":"none","type":"merged","plan_slug":"has-real-ask","task_id":"","sha":"sha7","needs_you_id":"","session_id":"","summary":"s7","evidence_link":"","emitter":"workstreams-emit","provenance":"known","user":"u","machine":"m","repo":"r"}
EOP
  bash "$SCRIPT_DIR/remap-placeholder-ask-events.sh" >/dev/null 2>&1
  if grep -qF '"event_id":"evt-7"' "$PROGRESS_LOG_STATE_DIR/ask-real-123.jsonl" 2>/dev/null; then
    pass "a none.jsonl event whose plan has a real ask-id was re-homed to that ask's file by the default run"
  else
    fail "expected evt-7 in ask-real-123.jsonl — the default run did not drain none.jsonl"
  fi
  if [[ ! -f "$PROGRESS_LOG_STATE_DIR/none.jsonl" ]] && [[ -f "$PROGRESS_LOG_STATE_DIR/none.jsonl.migrated" ]]; then
    pass "none.jsonl was renamed away with its own receipt marker (none.jsonl.migrated)"
  else
    fail "none.jsonl not cleanly migrated (file present: $([[ -f "$PROGRESS_LOG_STATE_DIR/none.jsonl" ]] && echo yes || echo no); marker present: $([[ -f "$PROGRESS_LOG_STATE_DIR/none.jsonl.migrated" ]] && echo yes || echo no))"
  fi

  echo "Scenario H: REBORN-SOURCE GUARD — a source file that exists AGAIN after its migration completed warns loudly, exits nonzero, and leaves the file untouched (a pre-fix emitter is still live)"
  cat >"$PROGRESS_LOG_STATE_DIR/none.jsonl" <<EOP
{"v":1,"event_id":"evt-8","ts":"2026-07-14T00:07:00Z","ask_id":"none","type":"task_started","plan_slug":"has-real-ask","task_id":"","sha":"","needs_you_id":"","session_id":"sid8","summary":"s8","evidence_link":"","emitter":"workstreams-emit","provenance":"known","user":"u","machine":"m","repo":"r"}
EOP
  OUT_H_RC=0
  OUT_H="$(bash "$SCRIPT_DIR/remap-placeholder-ask-events.sh" 2>&1)" || OUT_H_RC=$?
  if [[ "$OUT_H_RC" != "0" ]] && printf '%s' "$OUT_H" | grep -q "EXISTS AGAIN"; then
    pass "reborn none.jsonl after a completed migration produced the loud warning and a nonzero exit"
  else
    fail "expected 'EXISTS AGAIN' warning + nonzero exit (got rc=$OUT_H_RC); output: $OUT_H"
  fi
  if [[ -f "$PROGRESS_LOG_STATE_DIR/none.jsonl" ]] && grep -qF '"event_id":"evt-8"' "$PROGRESS_LOG_STATE_DIR/none.jsonl"; then
    pass "the reborn source file was left untouched (no stranded/lost events)"
  else
    fail "the reborn none.jsonl was modified or removed — the guard must never touch a reborn source"
  fi
  rm -f "$PROGRESS_LOG_STATE_DIR/none.jsonl" 2>/dev/null

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry point
# ============================================================
case "${1:-}" in
  --self-test|--selftest|selftest|self-test)
    cmd_selftest
    exit $?
    ;;
  --dry-run)
    # Dual-source default (re-review 2026-07-28): the sentinel class has
    # two live misfiled targets — _id.jsonl (truncated '<id' placeholder)
    # and none.jsonl (the documented 'none — no linked ask' spelling,
    # sanitized into a real-looking filename by pre-fix hooks).
    cmd_run --dry-run --source _id.jsonl
    cmd_run --dry-run --source none.jsonl
    exit 0
    ;;
  -h|--help)
    cat <<'USAGE'
remap-placeholder-ask-events.sh — one-shot, idempotent repair for the
2026-07-27 progress-log emitter bug (events filed under the literal
placeholder ask-id "<id" in _id.jsonl).

Usage:
  remap-placeholder-ask-events.sh             Run the migration for real
                                              (both sources: _id.jsonl AND none.jsonl).
  remap-placeholder-ask-events.sh --dry-run    Report projected moves; no changes.
  remap-placeholder-ask-events.sh --self-test  Run the sandboxed self-test suite.

Ordering law: install the FIXED hooks live before the real run — a still-live
pre-fix emitter regrows the source file; the reborn-source guard detects this
(warns + exits nonzero) rather than stranding the new events behind the
already-migrated receipt marker.

See this file's own header comment for the full bug story and repair logic.
USAGE
    exit 0
    ;;
  "")
    # Nonzero if EITHER source hits the reborn-source guard (a pre-fix
    # emitter is still live) — honest exit for a manually-run repair tool.
    rc=0
    cmd_run --source _id.jsonl || rc=$?
    cmd_run --source none.jsonl || rc=$?
    exit "$rc"
    ;;
  *)
    echo "remap-placeholder-ask-events.sh: unknown argument '$1' (run --help for usage; never blocks a caller)" >&2
    exit 0
    ;;
esac
