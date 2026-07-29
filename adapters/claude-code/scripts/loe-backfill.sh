#!/bin/bash
# loe-backfill.sh — Accountable Estate program, T7 (docs/plans/
# accountable-estate-program-2026-07.md): LOE v1, per-PLAN actuals mining.
#
# ============================================================
# WHAT THIS IS / WHAT IT IS NOT (Chesterton's Fence for the next reader)
# ============================================================
#
# Architecture review F11 (docs/reviews/2026-07-27-accountable-estate-
# architecture-review.md, binding): "v1 = per-PLAN classing (3-5 classes,
# plan-level P50/P90 bands + the concentration flag) mined from plan
# evidence + git history. Per-task token attribution from interleaved
# transcripts is noise-dominated; go finer only after v1 proves out."
#
# This script mines docs/plans/archive/*.md (the ~161 completed plans, as
# of this build) + each plan's companion evidence artifact (a sibling
# `<slug>-evidence.md` prose log, or a `<slug>-evidence/` directory of
# `<n>.evidence.json` structured records — both shapes exist in this repo)
# + this repo's own git history, into per-plan actuals, then rolls those
# actuals up into a calibration table: P50/P90 bands per class + a
# concentration flag. It is READ-ONLY over the repo: its only write is its
# own output artifact (docs/plans/loe-calibration.json /.md), controlled by
# --out-json/--out-md. It never edits a plan file, never touches git state
# beyond `git log` reads, and ships a `git config core.hooksPath ""`
# sandboxed --self-test per the house fixture-repo convention (memory:
# "Global hooksPath fires in all test fixtures").
#
# It is NOT the plan-reviewer surfacing half (that is Check 18 in
# plan-reviewer.sh, extended in this same commit) and NOT the close-side
# "actuals append at close" half (that is close-plan.sh territory, T4's
# family, owned by the other machine in this WIP-1 slice — see the
# documented seam at the bottom of this header). It is also NOT per-task
# token attribution from transcripts — F11 explicitly defers that past v1.
#
# ============================================================
# CLASSIFICATION (deterministic, bash+jq — never an LLM judgment call)
# ============================================================
#
# 5 plan-level reference classes, checked in this priority order against
# the plan's `Mode:` header + its `## Files to Modify/Create` section body
# (case-insensitive keyword match; first match wins):
#   1. schema-migration  — \.sql\b|migration|schema[- ]change|alter table|create table
#   2. ui-feature         — \.tsx|\.jsx|src/components|src/app/|frontend/|\.vue\b
#   3. harness-mechanism  — adapters/claude-code/(hooks|scripts)|self-test
#   4. design-only        — Mode: design AND none of the above matched
#   5. general-multi-file — fallback (catch-all; everything else)
# This is an empirical, coarse classifier chosen for zero false negatives
# on "what kind of artifact did this plan touch" — it will misclassify a
# handful of mixed plans (e.g. a harness hook that also touches a .tsx
# UI); documented as a known limitation rather than hidden. Reclassifying
# a specific plan is a one-line override, not implemented in v1 (F11: "go
# finer only after v1 proves out").
#
# ============================================================
# ACTUALS MINED PER PLAN (honest-data law: unrecoverable = null, never
# imputed; a coverage % is always reported alongside the bands)
# ============================================================
#
#   task_count        — count of `- [x]` lines in the plan file (completed
#                        checkboxes across the whole file; archived plans
#                        are terminal so this includes the Definition-of-
#                        Done checkbox(es) too — a small, documented,
#                        constant-ish overcount, not worth a second regex
#                        pass to strip out for a v1 calibration prior).
#   wall_clock_days    — `git log --follow --format=%aI -- <path>` on the
#                        ARCHIVED file path (git's rename-following covers
#                        the docs/plans/<slug>.md -> docs/plans/archive/
#                        <slug>.md move plan-lifecycle.sh / close-plan.sh
#                        perform); first commit to last commit, in days.
#                        Chosen over commit-message slug-grep (tested and
#                        rejected: cross-plan false-positive mentions, e.g.
#                        "T9 acceptance S4 — became-link targets the PLAN
#                        slug" in an unrelated plan's commit, inflate the
#                        span) — the file's own commit history is the
#                        lowest-noise signal actually available.
#   builder_sessions   — count of DISTINCT `worktree agent-<id>` / "builder
#                        session, worktree <id>" substrings found in the
#                        plan file + its companion prose evidence file (the
#                        recorded convention, e.g. archive/ask-rooted-
#                        workstreams-p1-evidence.md:283 "Built at: ...
#                        (builder session, worktree agent-ace19d4a1edcb2958)").
#                        The structured `<slug>-evidence/*.evidence.json`
#                        shape records `commit_sha`, not a worktree/session
#                        id, so it does NOT contribute to this field —
#                        conflating the two would silently impute a count
#                        this repo never actually recorded.
#   tokens             — best-effort regex for an explicit token count
#                        (`<number>k? tokens`) in the plan + evidence text.
#                        Expected near-zero coverage — no evidence file
#                        surveyed at build time recorded one — reported
#                        honestly as a coverage % rather than hidden.
#
# ============================================================
# THE CLOSE-SIDE SEAM (documented, not built here — T4's family owns
# close-plan.sh; this WIP-1 slice must not touch admission/dispatch/
# closer files)
# ============================================================
#
# "actuals append at close" (this plan's T7 outcome-metric second half) is
# trivially satisfiable WITHOUT touching close-plan.sh's own logic, because
# this script's default mode is a full, idempotent, deterministic re-mine
# of the whole archive (no incremental state to drift or corrupt). The
# seam: adapters/claude-code/scripts/close-plan.sh's cmd_close() function,
# immediately after its closure-commit block (close-plan.sh:~1286, the line
# right before the existing `emit_plan_completed_progress_log_event`
# call at close-plan.sh:1293), should add one non-fatal line:
#   bash adapters/claude-code/scripts/loe-backfill.sh >/dev/null 2>&1 || true
# mirroring the `|| true`-guarded splice pattern T3's admission-lib callers
# already use (hooks/workstreams-emit.sh, scripts/session-resumer.sh,
# scripts/spawn-worktree.sh) so a broken miner never blocks a plan closure.
# NOT implemented in this commit — close-plan.sh is out of this task's
# scope per the operator's WIP-1 directive.
#
# ============================================================
# Exit codes: 0 success (mine or self-test). 1 self-test failure.
# 2 usage/input error.
# ============================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------
# lb_repo_root: resolve the repo root without assuming CWD. Read-only
# (git rev-parse only inspects, never mutates).
# ------------------------------------------------------------
lb_repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
  else
    pwd
  fi
}

# ------------------------------------------------------------
# lb_header_field: extract a `Field: value` plan-header line. Mirrors the
# awk convention plan-reviewer.sh Check 10 already uses (grep -P is not
# portable to Windows Git Bash's grep).
# ------------------------------------------------------------
lb_header_field() {
  local file="$1" field="$2"
  awk -F: -v pat="^${field}:" '
    $0 ~ pat {
      sub(pat, "", $0)
      sub(/^[ \t]+/, "", $0)
      sub(/[ \t]+$/, "", $0)
      print $0
      exit
    }
  ' "$file" 2>/dev/null
}

# ------------------------------------------------------------
# lb_section: extract the body of a `## Heading` section (from the next
# line after the heading to the next `## ` heading or EOF). Loose prefix
# match on the heading (`## Files to Modify` matches both "Files to
# Modify/Create" and "Files to Modify" variants observed in the corpus).
# ------------------------------------------------------------
lb_section() {
  local file="$1" heading_prefix="$2"
  awk -v hp="$heading_prefix" '
    BEGIN { flag = 0 }
    $0 ~ ("^## " hp) { flag = 1; next }
    /^## / { if (flag) exit }
    flag { print }
  ' "$file" 2>/dev/null
}

# ------------------------------------------------------------
# lb_classify: 5-class deterministic classifier. See header comment for
# the priority order and rationale.
# ------------------------------------------------------------
lb_classify() {
  local mode="$1" files_section="$2"
  local lc
  lc="$(printf '%s' "$files_section" | tr '[:upper:]' '[:lower:]')"

  if printf '%s' "$lc" | grep -qE '\.sql\b|migration|schema[- ]change|alter table|create table'; then
    printf '%s\n' "schema-migration"
    return
  fi
  if printf '%s' "$lc" | grep -qE '\.tsx|\.jsx|src/components|src/app/|frontend/|\.vue\b'; then
    printf '%s\n' "ui-feature"
    return
  fi
  if printf '%s' "$lc" | grep -qE 'adapters/claude-code/(hooks|scripts)|self-test'; then
    printf '%s\n' "harness-mechanism"
    return
  fi
  if [[ "$mode" == "design" ]]; then
    printf '%s\n' "design-only"
    return
  fi
  printf '%s\n' "general-multi-file"
}

# ------------------------------------------------------------
# lb_task_count: count of completed-checkbox lines in the whole plan file.
# ------------------------------------------------------------
lb_task_count() {
  local file="$1"
  # NOTE: grep -c always prints a count (including "0") regardless of
  # whether it matched; its EXIT STATUS (not stdout) signals match/no-match
  # (1 = zero matches). An `|| echo 0` fallback here is a real bug, not
  # defensive redundancy: on zero matches grep already printed "0" AND
  # returned exit 1, so the fallback fires TOO, emitting a second "0\n0"
  # line that breaks the caller's `--argjson` (invalid JSON: two values).
  # Found live on the real corpus (a plan with zero recognized checkbox
  # lines) — no fixture in --self-test happened to hit zero matches, so
  # this shipped invisibly until the real mining run.
  grep -cE '^[[:space:]]*-[[:space:]]*\[[xX]\]' "$file" 2>/dev/null
}

# ------------------------------------------------------------
# lb_wall_clock: prints "first_iso last_iso" (space-separated) using ONE
# `git log --follow` invocation (the dominant per-file cost — measured at
# ~3.4s/file on this machine; a second invocation per file would double
# mining wall-clock for no benefit). Empty output if the path has no git
# history (should not happen for a committed archived plan, but handled
# honestly rather than assumed).
# ------------------------------------------------------------
lb_wall_clock() {
  local repo_root="$1" relpath="$2"
  local log
  log="$(cd "$repo_root" && git log --follow --format=%aI -- "$relpath" 2>/dev/null)"
  if [[ -z "$log" ]]; then
    return
  fi
  local first last
  first="$(printf '%s\n' "$log" | tail -1)"
  last="$(printf '%s\n' "$log" | head -1)"
  printf '%s %s\n' "$first" "$last"
}

# ------------------------------------------------------------
# lb_wall_clock_days: first_iso last_iso -> days (decimal, via awk; date
# -d is GNU/coreutils, present in Git Bash on Windows and Linux alike).
# ------------------------------------------------------------
lb_wall_clock_days() {
  local first="$1" last="$2"
  local f_epoch l_epoch
  f_epoch="$(date -d "$first" +%s 2>/dev/null)"
  l_epoch="$(date -d "$last" +%s 2>/dev/null)"
  if [[ -z "$f_epoch" || -z "$l_epoch" ]]; then
    return
  fi
  awk -v f="$f_epoch" -v l="$l_epoch" 'BEGIN { printf "%.2f", (l - f) / 86400 }'
}

# ------------------------------------------------------------
# lb_builder_sessions: distinct `worktree agent-<id>` / `worktree <id>`
# builder-session markers across the plan file + its companion prose
# evidence file (if present). Empty (not 0) if none found anywhere —
# honest null, never a false "zero sessions".
# ------------------------------------------------------------
lb_builder_sessions() {
  local plan_file="$1" evidence_file="$2"
  local combined
  combined=""
  if [[ -f "$plan_file" ]]; then
    combined+="$(cat "$plan_file" 2>/dev/null)"$'\n'
  fi
  if [[ -n "$evidence_file" && -f "$evidence_file" ]]; then
    combined+="$(cat "$evidence_file" 2>/dev/null)"$'\n'
  fi
  if [[ -z "$combined" ]]; then
    return
  fi
  local count
  count="$(printf '%s' "$combined" | grep -oE 'worktree[[:space:]]+agent-[A-Za-z0-9]+' | sort -u | wc -l | tr -d '[:space:]')"
  if [[ "$count" == "0" ]]; then
    return
  fi
  printf '%s\n' "$count"
}

# ------------------------------------------------------------
# lb_tokens: best-effort explicit token-count extraction. Returns the
# LARGEST number found (a plan's final token tally is usually the most
# meaningful single figure if any is recorded at all). Empty if none.
# ------------------------------------------------------------
lb_tokens() {
  local plan_file="$1" evidence_file="$2"
  local combined
  combined=""
  if [[ -f "$plan_file" ]]; then
    combined+="$(cat "$plan_file" 2>/dev/null)"$'\n'
  fi
  if [[ -n "$evidence_file" && -f "$evidence_file" ]]; then
    combined+="$(cat "$evidence_file" 2>/dev/null)"$'\n'
  fi
  if [[ -z "$combined" ]]; then
    return
  fi
  local matches
  matches="$(printf '%s' "$combined" | grep -oiE '[0-9][0-9,.]*k?[[:space:]]*tokens' 2>/dev/null)"
  if [[ -z "$matches" ]]; then
    return
  fi
  # Normalize each match to a raw number (strip 'k' suffix -> *1000, strip
  # commas/the word tokens), then print the max via awk.
  printf '%s\n' "$matches" | awk '
    {
      raw = $0
      gsub(/[Tt][Oo][Kk][Ee][Nn][Ss]/, "", raw)
      gsub(/[[:space:]]/, "", raw)
      mult = 1
      if (raw ~ /[kK]$/) { mult = 1000; gsub(/[kK]$/, "", raw) }
      gsub(/,/, "", raw)
      val = raw * mult
      if (val > max) max = val
    }
    END { if (max > 0) printf "%d", max }
  '
}

# ------------------------------------------------------------
# lb_mine_one: emit one JSON object (single line) for one archived plan.
# Args: repo_root archive_dir plan_basename(no dir, with .md)
# ------------------------------------------------------------
lb_mine_one() {
  local repo_root="$1" archive_dir="$2" basename="$3"
  local plan_file="${archive_dir}/${basename}"
  local slug="${basename%.md}"
  local relpath
  relpath="$(printf '%s' "$plan_file" | sed "s#^${repo_root}/##")"

  local mode files_section class task_count
  mode="$(lb_header_field "$plan_file" "Mode")"
  files_section="$(lb_section "$plan_file" "Files to Modify")"
  class="$(lb_classify "$mode" "$files_section")"
  task_count="$(lb_task_count "$plan_file")"

  local evidence_file=""
  if [[ -f "${archive_dir}/${slug}-evidence.md" ]]; then
    evidence_file="${archive_dir}/${slug}-evidence.md"
  fi
  local has_evidence="false"
  if [[ -n "$evidence_file" ]] || [[ -d "${archive_dir}/${slug}-evidence" ]]; then
    has_evidence="true"
  fi

  local wc_pair first_iso="" last_iso="" wc_days=""
  wc_pair="$(lb_wall_clock "$repo_root" "$relpath")"
  if [[ -n "$wc_pair" ]]; then
    first_iso="${wc_pair% *}"
    last_iso="${wc_pair#* }"
    wc_days="$(lb_wall_clock_days "$first_iso" "$last_iso")"
  fi

  local sessions tokens
  sessions="$(lb_builder_sessions "$plan_file" "$evidence_file")"
  tokens="$(lb_tokens "$plan_file" "$evidence_file")"

  jq -n \
    --arg slug "$slug" \
    --arg mode "${mode:-}" \
    --arg class "$class" \
    --argjson task_count "${task_count:-0}" \
    --arg wall_clock_days "$wc_days" \
    --arg first_commit "$first_iso" \
    --arg last_commit "$last_iso" \
    --arg builder_sessions "$sessions" \
    --arg tokens "$tokens" \
    --argjson has_evidence "$has_evidence" \
    '{
      slug: $slug,
      mode: (if $mode == "" then null else $mode end),
      class: $class,
      task_count: $task_count,
      wall_clock_days: (if $wall_clock_days == "" then null else ($wall_clock_days | tonumber) end),
      first_commit: (if $first_commit == "" then null else $first_commit end),
      last_commit: (if $last_commit == "" then null else $last_commit end),
      builder_sessions: (if $builder_sessions == "" then null else ($builder_sessions | tonumber) end),
      tokens: (if $tokens == "" then null else ($tokens | tonumber) end),
      has_evidence: $has_evidence
    }'
}

# ------------------------------------------------------------
# JQ aggregation program (per-plan array -> calibration table). Kept as a
# single embedded filter (no companion file — this is a single-artifact
# deliverable) so --self-test and real runs exercise the exact same code.
# ------------------------------------------------------------
read -r -d '' LB_JQ_AGG <<'JQEOF'
def pct(p):
  if length == 0 then null
  else
    (sort) as $s
    | ((($s | length) - 1) * p | floor) as $i
    | $s[$i]
  end;

def band(vals):
  {
    p50: (vals | pct(0.5)),
    p90: (vals | pct(0.9)),
    n: (vals | length)
  };

. as $all
| ($all | length) as $total
| ($all | group_by(.class) | map({
    class: .[0].class,
    count: length,
    task_count: (band([.[] | select(.task_count != null) | .task_count])),
    wall_clock_days: (band([.[] | select(.wall_clock_days != null) | .wall_clock_days])),
    builder_sessions: (
      band([.[] | select(.builder_sessions != null) | .builder_sessions])
      + { coverage_pct: (
            (([.[] | select(.builder_sessions != null)] | length) * 100.0 / length)
            | (. * 10 | round) / 10
          ) }
    ),
    concentration_flag: (
      ([.[] | select(.wall_clock_days != null) | .wall_clock_days]) as $vals
      | if ($vals | length) >= 2 and (($vals | add) > 0)
        then (($vals | max) > (($vals | add) * 0.5))
        else false
        end
    )
  })) as $classes
| {
    generated_at: $now,
    plans_total: $total,
    coverage: {
      wall_clock_pct: ((($all | map(select(.wall_clock_days != null)) | length) * 100.0 / $total) | (. * 10 | round) / 10),
      builder_sessions_pct: ((($all | map(select(.builder_sessions != null)) | length) * 100.0 / $total) | (. * 10 | round) / 10),
      tokens_pct: ((($all | map(select(.tokens != null)) | length) * 100.0 / $total) | (. * 10 | round) / 10)
    },
    classes: $classes,
    per_plan: $all
  }
JQEOF

# ------------------------------------------------------------
# lb_render_md: render the JSON calibration table into a scannable
# Markdown summary (house law: lists/tables, no paragraphs).
# ------------------------------------------------------------
lb_render_md() {
  local json_file="$1"
  echo "# LOE calibration table (per-PLAN, v1)"
  echo
  echo "Generated: $(jq -r '.generated_at' "$json_file")"
  echo "Plans mined: $(jq -r '.plans_total' "$json_file")"
  echo "Coverage: wall-clock $(jq -r '.coverage.wall_clock_pct' "$json_file")% · builder-sessions $(jq -r '.coverage.builder_sessions_pct' "$json_file")% · tokens $(jq -r '.coverage.tokens_pct' "$json_file")%"
  echo
  echo "| Class | Count | Task count P50/P90 | Wall-clock days P50/P90 | Builder-sessions P50/P90 (coverage) | Concentration |"
  echo "|---|---|---|---|---|---|"
  jq -r '.classes[] | [
    .class,
    (.count|tostring),
    ((.task_count.p50|tostring) + "/" + (.task_count.p90|tostring)),
    ((.wall_clock_days.p50|tostring) + "/" + (.wall_clock_days.p90|tostring)),
    ((.builder_sessions.p50|tostring) + "/" + (.builder_sessions.p90|tostring) + " (" + (.builder_sessions.coverage_pct|tostring) + "%)"),
    (.concentration_flag|tostring)
  ] | "| " + join(" | ") + " |"' "$json_file"
  echo
  echo "Honest-data note: null bands mean zero plans in that class recorded the"
  echo "signal (no evidence file, no token counts) — never imputed. See the"
  echo "coverage line above and \`per_plan\` in the JSON for per-plan detail."
}

# ------------------------------------------------------------
# cmd_mine: full pipeline. Args: repo_root archive_dir out_json out_md
# ------------------------------------------------------------
cmd_mine() {
  local repo_root="$1" archive_dir="$2" out_json="$3" out_md="$4"

  if [[ ! -d "$archive_dir" ]]; then
    echo "loe-backfill: archive dir not found: $archive_dir" >&2
    return 2
  fi

  local jsonl_tmp
  jsonl_tmp="$(mktemp)"
  trap 'rm -f "$jsonl_tmp"' RETURN

  local f base
  for f in "$archive_dir"/*.md; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    case "$base" in
      *-evidence.md) continue ;;
    esac
    lb_mine_one "$repo_root" "$archive_dir" "$base" >> "$jsonl_tmp"
  done

  if [[ ! -s "$jsonl_tmp" ]]; then
    echo "loe-backfill: no plans found under $archive_dir" >&2
    return 2
  fi

  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$out_json")"
  jq -s --arg now "$now" "$LB_JQ_AGG" "$jsonl_tmp" > "$out_json"
  lb_render_md "$out_json" > "$out_md"
  echo "loe-backfill: mined $(jq -r '.plans_total' "$out_json" 2>/dev/null) plans -> $out_json, $out_md" >&2
}

# ============================================================
# --self-test
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  TMPDIR_SELFTEST="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT
  FAILED=0

  SYNTH="$TMPDIR_SELFTEST/repo"
  mkdir -p "$SYNTH/docs/plans/archive"
  ( cd "$SYNTH" && git init -q . && git config core.hooksPath "" && git config user.email t@example.test && git config user.name T ) >/dev/null 2>&1

  # ---- Fixture A: harness-mechanism plan, WITH prose evidence recording
  # 2 distinct builder sessions, spanning 3 days of commits.
  mkdir -p "$SYNTH/docs/plans"
  cat > "$SYNTH/docs/plans/plan-a.md" <<'EOF'
# Plan: Fixture A
Status: ACTIVE
Mode: code

## Goal
Ship a new hook with a self-test.

## Files to Modify/Create
- `adapters/claude-code/hooks/foo.sh` (NEW) — self-test included

## Tasks
- [x] 1. Write the hook.
- [x] 2. Wire it into settings.json.template.

## Definition of Done
- [x] Self-test passes.
EOF
  ( cd "$SYNTH" && git add docs/plans/plan-a.md && GIT_AUTHOR_DATE="2026-01-01T10:00:00" GIT_COMMITTER_DATE="2026-01-01T10:00:00" git commit -q -m "plan(a): create" ) >/dev/null 2>&1
  mkdir -p "$SYNTH/docs/plans/archive"
  ( cd "$SYNTH" && git mv docs/plans/plan-a.md docs/plans/archive/plan-a.md ) >/dev/null 2>&1
  cat > "$SYNTH/docs/plans/archive/plan-a-evidence.md" <<'EOF'
# Evidence Log - Fixture A
Task 1: Built at: 2026-01-02 (builder session, worktree agent-aaa111)
Task 2: Built at: 2026-01-03 (builder session, worktree agent-bbb222)
EOF
  ( cd "$SYNTH" && git add docs/plans/archive/plan-a.md docs/plans/archive/plan-a-evidence.md && GIT_AUTHOR_DATE="2026-01-04T10:00:00" GIT_COMMITTER_DATE="2026-01-04T10:00:00" git commit -q -m "plan(a): close" ) >/dev/null 2>&1

  # ---- Fixture B: ui-feature plan, NO evidence file at all (tests the
  # honest-null path — task_count still recoverable, everything else null).
  cat > "$SYNTH/docs/plans/plan-b.md" <<'EOF'
# Plan: Fixture B
Status: ACTIVE
Mode: code

## Goal
Ship a UI button.

## Files to Modify/Create
- `src/components/Button.tsx` — new button

## Tasks
- [x] 1. Add the button.

## Definition of Done
- [x] Button renders.
EOF
  ( cd "$SYNTH" && git add docs/plans/plan-b.md && GIT_AUTHOR_DATE="2026-02-01T10:00:00" GIT_COMMITTER_DATE="2026-02-01T10:00:00" git commit -q -m "plan(b): create" ) >/dev/null 2>&1
  ( cd "$SYNTH" && git mv docs/plans/plan-b.md docs/plans/archive/plan-b.md && GIT_AUTHOR_DATE="2026-02-02T10:00:00" GIT_COMMITTER_DATE="2026-02-02T10:00:00" git commit -q -m "plan(b): close" ) >/dev/null 2>&1

  # ---- Fixture C: design-only plan (Mode: design, no code files) — a
  # second harness-mechanism-free class so the classifier's design-only
  # branch is exercised.
  cat > "$SYNTH/docs/plans/plan-c.md" <<'EOF'
# Plan: Fixture C
Status: ACTIVE
Mode: design

## Goal
Review an architecture proposal.

## Files to Modify/Create
- `docs/designs/foo-design.md` — the design doc itself

## Tasks
- [x] 1. Write the design doc.

## Definition of Done
- [x] Review lands.
EOF
  ( cd "$SYNTH" && git add docs/plans/plan-c.md && GIT_AUTHOR_DATE="2026-03-01T10:00:00" GIT_COMMITTER_DATE="2026-03-01T10:00:00" git commit -q -m "plan(c): create" ) >/dev/null 2>&1
  ( cd "$SYNTH" && git mv docs/plans/plan-c.md docs/plans/archive/plan-c.md && GIT_AUTHOR_DATE="2026-03-05T10:00:00" GIT_COMMITTER_DATE="2026-03-05T10:00:00" git commit -q -m "plan(c): close" ) >/dev/null 2>&1

  # ---- Fixture D: ZERO completed-checkbox lines (regression fixture for
  # the grep -c exit-status bug: grep -c prints "0" on no match but ALSO
  # returns exit 1, so an `|| echo 0` fallback double-emits and breaks the
  # caller's --argjson — found live on the real corpus, not by any
  # fixture until this one was added).
  cat > "$SYNTH/docs/plans/plan-d.md" <<'EOF'
# Plan: Fixture D
Status: ACTIVE
Mode: code

## Goal
Regression fixture for the zero-checkbox task_count path.

## Files to Modify/Create
- `docs/notes/foo.md` — a note, no checkboxes anywhere in this plan

## Tasks
- Nothing to check off; this fixture intentionally has zero `- [x]` lines.
EOF
  ( cd "$SYNTH" && git add docs/plans/plan-d.md && GIT_AUTHOR_DATE="2026-04-01T10:00:00" GIT_COMMITTER_DATE="2026-04-01T10:00:00" git commit -q -m "plan(d): create" ) >/dev/null 2>&1
  ( cd "$SYNTH" && git mv docs/plans/plan-d.md docs/plans/archive/plan-d.md && GIT_AUTHOR_DATE="2026-04-02T10:00:00" GIT_COMMITTER_DATE="2026-04-02T10:00:00" git commit -q -m "plan(d): close" ) >/dev/null 2>&1

  OUT_JSON="$TMPDIR_SELFTEST/out.json"
  OUT_MD="$TMPDIR_SELFTEST/out.md"
  cmd_mine "$SYNTH" "$SYNTH/docs/plans/archive" "$OUT_JSON" "$OUT_MD"

  # Scenario 1: 4 plans mined, plans_total == 4.
  if [[ "$(jq -r '.plans_total' "$OUT_JSON" 2>/dev/null)" == "4" ]]; then
    echo "self-test (1) plans_total==4: PASS (expected)" >&2
  else
    echo "self-test (1) plans_total==4: FAIL (expected), got: $(jq -r '.plans_total' "$OUT_JSON" 2>/dev/null)" >&2
    FAILED=1
  fi

  # Scenario 1b: plan-d (zero `- [x]` lines) mines with task_count == 0
  # and does NOT crash jq's --argjson (the exact bug found on the real
  # corpus: grep -c prints "0" on no-match but exits 1, so a naive
  # `|| echo 0` fallback double-emits "0\n0" and breaks --argjson).
  D_TASKS="$(jq -r '.per_plan[] | select(.slug=="plan-d") | .task_count' "$OUT_JSON" 2>/dev/null)"
  if [[ "$D_TASKS" == "0" ]]; then
    echo "self-test (1b) plan-d zero-checkbox task_count==0 no crash: PASS (expected)" >&2
  else
    echo "self-test (1b) plan-d zero-checkbox task_count==0 no crash: FAIL (expected 0, got $D_TASKS)" >&2
    FAILED=1
  fi

  # Scenario 2: plan-a classified harness-mechanism, task_count 3
  # (2 Tasks + 1 DoD checkbox, per the documented whole-file count).
  A_CLASS="$(jq -r '.per_plan[] | select(.slug=="plan-a") | .class' "$OUT_JSON" 2>/dev/null)"
  A_TASKS="$(jq -r '.per_plan[] | select(.slug=="plan-a") | .task_count' "$OUT_JSON" 2>/dev/null)"
  if [[ "$A_CLASS" == "harness-mechanism" && "$A_TASKS" == "3" ]]; then
    echo "self-test (2) plan-a class+task_count: PASS (expected)" >&2
  else
    echo "self-test (2) plan-a class+task_count: FAIL (expected harness-mechanism/3, got $A_CLASS/$A_TASKS)" >&2
    FAILED=1
  fi

  # Scenario 3: plan-a builder_sessions == 2 (distinct worktree agent ids).
  A_SESSIONS="$(jq -r '.per_plan[] | select(.slug=="plan-a") | .builder_sessions' "$OUT_JSON" 2>/dev/null)"
  if [[ "$A_SESSIONS" == "2" ]]; then
    echo "self-test (3) plan-a builder_sessions==2: PASS (expected)" >&2
  else
    echo "self-test (3) plan-a builder_sessions==2: FAIL (expected 2, got $A_SESSIONS)" >&2
    FAILED=1
  fi

  # Scenario 4: plan-a wall_clock_days == 3.00 (2026-01-01 -> 2026-01-04).
  A_WC="$(jq -r '.per_plan[] | select(.slug=="plan-a") | .wall_clock_days' "$OUT_JSON" 2>/dev/null)"
  if [[ "$A_WC" == "3" || "$A_WC" == "3.0" || "$A_WC" == "3.00" ]]; then
    echo "self-test (4) plan-a wall_clock_days==3: PASS (expected)" >&2
  else
    echo "self-test (4) plan-a wall_clock_days==3: FAIL (expected 3, got $A_WC)" >&2
    FAILED=1
  fi

  # Scenario 5: plan-b classified ui-feature, builder_sessions is null
  # (honest-null path — no evidence file at all).
  B_CLASS="$(jq -r '.per_plan[] | select(.slug=="plan-b") | .class' "$OUT_JSON" 2>/dev/null)"
  B_SESSIONS="$(jq -r '.per_plan[] | select(.slug=="plan-b") | .builder_sessions' "$OUT_JSON" 2>/dev/null)"
  if [[ "$B_CLASS" == "ui-feature" && "$B_SESSIONS" == "null" ]]; then
    echo "self-test (5) plan-b class+honest-null-sessions: PASS (expected)" >&2
  else
    echo "self-test (5) plan-b class+honest-null-sessions: FAIL (expected ui-feature/null, got $B_CLASS/$B_SESSIONS)" >&2
    FAILED=1
  fi

  # Scenario 6: plan-c classified design-only.
  C_CLASS="$(jq -r '.per_plan[] | select(.slug=="plan-c") | .class' "$OUT_JSON" 2>/dev/null)"
  if [[ "$C_CLASS" == "design-only" ]]; then
    echo "self-test (6) plan-c design-only: PASS (expected)" >&2
  else
    echo "self-test (6) plan-c design-only: FAIL (expected design-only, got $C_CLASS)" >&2
    FAILED=1
  fi

  # Scenario 7: coverage.builder_sessions_pct reflects 1 of 4 plans (25.0%).
  COV="$(jq -r '.coverage.builder_sessions_pct' "$OUT_JSON" 2>/dev/null)"
  if [[ "$COV" == "25" || "$COV" == "25.0" ]]; then
    echo "self-test (7) coverage builder_sessions_pct==25.0: PASS (expected)" >&2
  else
    echo "self-test (7) coverage builder_sessions_pct==25.0: FAIL (expected 25.0, got $COV)" >&2
    FAILED=1
  fi

  # Scenario 8: 4 distinct classes present (harness-mechanism, ui-feature,
  # design-only, general-multi-file — plan-d's zero-signal Files section
  # falls through to the catch-all) — confirms the classifier is not
  # collapsing everything into one bucket (F11's "3-5 classes").
  NCLASSES="$(jq -r '.classes | length' "$OUT_JSON" 2>/dev/null)"
  if [[ "$NCLASSES" == "4" ]]; then
    echo "self-test (8) 4 distinct classes present: PASS (expected)" >&2
  else
    echo "self-test (8) 4 distinct classes present: FAIL (expected 4, got $NCLASSES)" >&2
    FAILED=1
  fi

  # Scenario 9: read-only guarantee — the synthetic repo's git status is
  # clean after mining (mining wrote ONLY to $OUT_JSON/$OUT_MD, both
  # OUTSIDE the synthetic repo).
  STATUS_AFTER="$(cd "$SYNTH" && git status --porcelain 2>/dev/null)"
  if [[ -z "$STATUS_AFTER" ]]; then
    echo "self-test (9) read-only over the mined repo: PASS (expected)" >&2
  else
    echo "self-test (9) read-only over the mined repo: FAIL (expected clean, got: $STATUS_AFTER)" >&2
    FAILED=1
  fi

  # Scenario 10: rendered Markdown contains the honest-data note (never
  # silently imputed) and the coverage line.
  if grep -q "never imputed" "$OUT_MD" 2>/dev/null && grep -q "Coverage:" "$OUT_MD" 2>/dev/null; then
    echo "self-test (10) markdown honest-data note present: PASS (expected)" >&2
  else
    echo "self-test (10) markdown honest-data note present: FAIL (expected)" >&2
    FAILED=1
  fi

  # Scenario 11: usage error on a missing archive dir exits non-zero.
  if cmd_mine "$SYNTH" "$SYNTH/docs/plans/does-not-exist" "$TMPDIR_SELFTEST/x.json" "$TMPDIR_SELFTEST/x.md" >/dev/null 2>&1; then
    echo "self-test (11) missing-archive-dir errors: FAIL (expected non-zero exit)" >&2
    FAILED=1
  else
    echo "self-test (11) missing-archive-dir errors: PASS (expected)" >&2
  fi

  if [[ $FAILED -eq 0 ]]; then
    echo "loe-backfill --self-test: all scenarios matched expectations" >&2
    exit 0
  else
    echo "loe-backfill --self-test: one or more scenarios failed" >&2
    exit 1
  fi
fi

# ============================================================
# CLI
# ============================================================
REPO_ROOT="$(lb_repo_root)"
ARCHIVE_DIR="${REPO_ROOT}/docs/plans/archive"
OUT_JSON="${REPO_ROOT}/docs/plans/loe-calibration.json"
OUT_MD="${REPO_ROOT}/docs/plans/loe-calibration.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --archive-dir) ARCHIVE_DIR="$2"; shift 2 ;;
    --out-json) OUT_JSON="$2"; shift 2 ;;
    --out-md) OUT_MD="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--repo-root DIR] [--archive-dir DIR] [--out-json PATH] [--out-md PATH]"
      echo "       $0 --self-test"
      exit 0
      ;;
    *)
      echo "loe-backfill: unrecognized argument: $1" >&2
      exit 2
      ;;
  esac
done

cmd_mine "$REPO_ROOT" "$ARCHIVE_DIR" "$OUT_JSON" "$OUT_MD"
exit $?
