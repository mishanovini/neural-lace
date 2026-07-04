#!/bin/bash
# session-snapshot.sh <transcript-path> — Wave E task E.9 (shared script, E.9a+E.9b).
#
# WHY THIS EXISTS: pre-compaction / near-context-limit continuity backstop. Writes
# a MECHANICAL (zero model-token) session-handoff file capturing exactly what a
# summarizer or a post-compaction SessionStart echo would otherwise have to
# reconstruct from fuzzy memory: git state, worktrees, open/in-flight background
# work, the ACTIVE plan's unchecked tasks, pending NEEDS-YOU items, and a
# SCRATCHPAD.md copy-in when it has gone stale. Pure shell — no LLM calls, no
# API cost — so it is safe to invoke proactively (E.9a's 85% watermark) or as
# part of the native PreCompact event (E.9b) without burning any of the budget
# it exists to protect.
#
# Output: ~/.claude/state/session-handoff/<session-id>.md (idempotent: re-running
# for the same session-id OVERWRITES, never appends/duplicates).
#
# Usage:
#   session-snapshot.sh <transcript-path>
#   session-snapshot.sh --self-test
#
# <transcript-path> is the JSONL transcript file for the CURRENT session (Claude
# Code hook input's `.transcript_path` field on every hook event that carries
# one — PostToolUse, PreCompact, Stop, etc.). The session-id is derived from the
# transcript's own JSON content first (each line/event carries `session_id`),
# falling back to the transcript's basename (`<session-id>.jsonl`) when no line
# parses (defensive; the basename convention is how Claude Code names these
# files today, but line-derivation is authoritative when both are present and
# they disagree — the file could in principle be a copy/fixture under a
# different name).
#
# Exit codes: 0 on success (including "wrote a best-effort snapshot despite a
# missing git repo / missing plan / missing NEEDS-YOU" — a PARTIAL snapshot is
# still useful and must never be treated as failure by a caller). Non-zero (1)
# only for genuine usage errors (missing/unreadable transcript-path argument)
# so a caller invoking this interactively gets a signal, while --self-test
# reports its own pass/fail summary via its own exit code.
#
# Categories mechanically captured here (NORMATIVE preserve-list categories 3
# and 5 per the plan's E.9 task + specs-e §E.9 — the categories requiring model
# judgment, (1)/(2)/(4)/(6), are NOT reconstructable from shell alone and are
# instead named as explicit instructions to the summarizer by the CALLER
# (pre-compact-continuity.sh); this script supplies the mechanical substrate
# those instructions point back at):
#   (3) exact execution state — git branch/HEAD/status, worktree list, in-flight
#       background work (report-back ids), specific next action (best-effort:
#       the ACTIVE plan's first unchecked task line, when resolvable).
#   (5) pending asks in BOTH directions — awaiting-operator (NEEDS-YOU.md
#       sections, when the file exists) + operator-awaiting is out of mechanical
#       reach (that is a live conversational state, category (1)'s domain) so
#       this script documents its absence honestly rather than fabricating it.

set -u

SCRIPT_NAME="session-snapshot.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../hooks/lib/nl-paths.sh
if [ -f "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/../hooks/lib/nl-paths.sh" 2>/dev/null || true
fi

# ============================================================
# Path / state helpers
# ============================================================

# Resolve the handoff output directory. Self-test sandboxes this via
# HARNESS_SELFTEST_DIR so no self-test run ever touches production state.
_handoff_dir() {
  if [ "${HARNESS_SELFTEST:-0}" = "1" ] && [ -n "${HARNESS_SELFTEST_DIR:-}" ]; then
    printf '%s/state/session-handoff' "$HARNESS_SELFTEST_DIR"
    return 0
  fi
  printf '%s/.claude/state/session-handoff' "$HOME"
}

# Resolve the MAIN checkout root for artifacts that live there by convention
# (SCRATCHPAD.md, docs/plans/, docs/backlog.md, NEEDS-YOU.md — ADR 028: worktrees
# are build isolation, not branch-lifetime contexts). Falls back to the CURRENT
# directory's toplevel when nl_main_checkout_root is unavailable or empty (e.g.
# running outside git entirely, or the lib failed to source).
_main_root() {
  if [ -n "${SESSION_SNAPSHOT_MAIN_ROOT:-}" ]; then
    printf '%s' "$SESSION_SNAPSHOT_MAIN_ROOT"
    return 0
  fi
  local root=""
  if command -v nl_main_checkout_root >/dev/null 2>&1; then
    root="$(nl_main_checkout_root 2>/dev/null || true)"
  fi
  if [ -z "$root" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  printf '%s' "$root"
}

# Derive session-id from a transcript path: prefer the `session_id` field from
# the LAST line that has one (authoritative — matches what the live hook input
# itself reports), fall back to the basename minus .jsonl.
_derive_session_id() {
  local transcript="$1" sid=""
  if [ -f "$transcript" ] && command -v jq >/dev/null 2>&1; then
    sid="$(tac "$transcript" 2>/dev/null | while IFS= read -r line; do
             printf '%s' "$line" | jq -r '.session_id // .sessionId // empty' 2>/dev/null
           done | grep -v '^$' | head -1)"
  fi
  if [ -z "$sid" ]; then
    sid="$(basename "$transcript" .jsonl)"
  fi
  printf '%s' "$sid"
}

# ============================================================
# Section builders — each echoes its own Markdown section, best-effort.
# Every builder is defensive: a missing tool/file/repo degrades to an honest
# "not available" line, never a script crash (this file always exits 0 on the
# happy usage path — see header).
# ============================================================

_section_git() {
  local main_root="${1:-}"
  echo "## 3a. Git state (this checkout)"
  # Resolve git state against main_root when given (test isolation / a caller
  # invoked from a cwd outside any repo, e.g. a fresh-HOME self-test sandbox
  # where $PWD is $HOME/.claude — NOT the repo). Falls back to the ambient cwd
  # when main_root is empty, preserving prior behavior for callers that don't
  # pass one.
  local -a gitc=()
  if [ -n "$main_root" ]; then
    gitc=(git -C "$main_root")
  else
    gitc=(git)
  fi
  if ! "${gitc[@]}" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "_not a git repository at snapshot time_"
    echo ""
    return 0
  fi
  local branch head dirty
  branch="$("${gitc[@]}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
  head="$("${gitc[@]}" rev-parse HEAD 2>/dev/null || echo "?")"
  echo "- Branch: \`${branch}\`"
  echo "- HEAD: \`${head}\`"
  echo "- Status (\`git status --porcelain\`):"
  echo '```'
  "${gitc[@]}" status --porcelain 2>/dev/null | head -100
  echo '```'
  dirty="$("${gitc[@]}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  echo "- Uncommitted entries: ${dirty}"
  echo ""
}

_section_worktrees() {
  local main_root="${1:-}"
  echo "## 3b. Worktrees"
  local -a gitc=()
  if [ -n "$main_root" ]; then
    gitc=(git -C "$main_root")
  else
    gitc=(git)
  fi
  if ! "${gitc[@]}" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "_not a git repository at snapshot time_"
    echo ""
    return 0
  fi
  echo '```'
  "${gitc[@]}" worktree list 2>/dev/null
  echo '```'
  echo ""
}

_section_open_tasks() {
  local main_root="$1"
  echo "## Open task list (task state files)"
  local found=0
  if [ -n "$main_root" ] && [ -d "$main_root/.claude/state" ]; then
    local d
    for d in orchestrator conversation-tree; do
      if [ -d "$main_root/.claude/state/$d" ] && find "$main_root/.claude/state/$d" -maxdepth 2 -type f 2>/dev/null | grep -q .; then
        found=1
        echo "- \`.claude/state/${d}/\` contains task-state files:"
        find "$main_root/.claude/state/$d" -maxdepth 2 -type f 2>/dev/null | sed 's/^/    - /'
      fi
    done
  fi
  if [ "$found" -eq 0 ]; then
    echo "_no task-state files found under .claude/state/ (orchestrator/conversation-tree) — none open, or this session predates their use_"
  fi
  echo ""
}

_section_inflight_background() {
  local main_root="$1"
  echo "## 3c. In-flight background work (report-back ids)"
  local dir="$main_root/.claude/state/spawned-task-results"
  if [ -z "$main_root" ] || [ ! -d "$dir" ]; then
    echo "_no spawned-task-results directory — no in-flight background work tracked_"
    echo ""
    return 0
  fi
  local any=0 f base
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    base="$(basename "$f" .json)"
    if [ -f "${f}.acked" ]; then
      continue
    fi
    any=1
    echo "- task-id=\`${base}\` — result written, NOT yet acknowledged (unread): ${f}"
  done
  if [ "$any" -eq 0 ]; then
    echo "_no unacknowledged spawned-task results — nothing in-flight is unaccounted for_"
  fi
  echo ""
}

_section_active_plan() {
  local main_root="$1"
  echo "## ACTIVE plan + unchecked tasks"
  if [ -z "$main_root" ] || [ ! -d "$main_root/docs/plans" ]; then
    echo "_no docs/plans directory found_"
    echo ""
    return 0
  fi
  local plan
  plan="$(ls -t "$main_root"/docs/plans/*.md 2>/dev/null | grep -v '/evidence' | grep -v '/archive/' | while IFS= read -r p; do
            status="$(grep -oE 'Status: [A-Za-z_-]+' "$p" 2>/dev/null | head -1 | sed 's/Status: //')"
            if [ "$status" = "ACTIVE" ]; then printf '%s\n' "$p"; fi
          done | head -1)"
  if [ -z "$plan" ]; then
    echo "_no ACTIVE plan found_"
    echo ""
    return 0
  fi
  local unchecked next
  unchecked="$(grep -c '^- \[ \]' "$plan" 2>/dev/null || echo 0)"
  next="$(grep -m1 '^- \[ \]' "$plan" 2>/dev/null || echo "")"
  echo "- Plan: \`${plan#$main_root/}\`"
  echo "- Unchecked tasks: ${unchecked}"
  if [ -n "$next" ]; then
    echo "- Specific next action (first unchecked task line):"
    echo "  > ${next}"
  fi
  echo ""
}

_section_needs_you() {
  local main_root="$1"
  echo "## Pending NEEDS-YOU items"
  local f="$main_root/NEEDS-YOU.md"
  if [ -z "$main_root" ] || [ ! -f "$f" ]; then
    echo "_NEEDS-YOU.md does not exist at the main-checkout root (E.6 not yet landed, or nothing pending)_"
    echo ""
    return 0
  fi
  echo "- Source: \`NEEDS-YOU.md\`"
  echo '```'
  head -80 "$f" 2>/dev/null
  echo '```'
  echo ""
}

_section_scratchpad() {
  local main_root="$1"
  echo "## SCRATCHPAD.md (copy-in if stale >30min)"
  local f="$main_root/SCRATCHPAD.md"
  if [ -z "$main_root" ] || [ ! -f "$f" ]; then
    echo "_no SCRATCHPAD.md found at the main-checkout root_"
    echo ""
    return 0
  fi
  local now mt age_min
  now=$(date +%s 2>/dev/null || echo 0)
  mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo "$now")
  age_min=$(( (now - mt) / 60 ))
  if [ "$age_min" -gt 30 ]; then
    echo "- STALE (mtime ${age_min} min ago > 30min threshold) — copying full contents in so nothing is lost to a stale pointer:"
    echo '```'
    cat "$f" 2>/dev/null
    echo '```'
  else
    echo "- Fresh (mtime ${age_min} min ago) — not copied in; read \`SCRATCHPAD.md\` directly."
  fi
  echo ""
}

# ============================================================
# Core build (used by both live path and self-test — takes an explicit
# main_root + output path so tests never depend on ambient HOME/cwd state
# beyond what they set up themselves)
# ============================================================
_build_snapshot() {
  local transcript="$1" session_id="$2" main_root="$3" out="$4"

  mkdir -p "$(dirname "$out")" 2>/dev/null || true

  {
    echo "# Session handoff snapshot"
    echo ""
    echo "- Session id: \`${session_id}\`"
    echo "- Transcript: \`${transcript}\`"
    echo "- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo ""
    echo "_Mechanically generated by session-snapshot.sh — zero model tokens. This file_"
    echo "_captures NORMATIVE preserve-list categories (3) exact execution state and (5)_"
    echo "_pending asks (awaiting-operator half only — see note below) from the plan's_"
    echo "_six-category list. Categories (1) operator directives, (2) decisions+rationale,_"
    echo "_(4) hard-learned constraints, (6) verified-vs-claimed status, and the_"
    echo "_operator-awaiting half of (5) require model judgment and are NOT reconstructable_"
    echo "_here — see the accompanying summarizer instructions for those._"
    echo ""
    _section_git "$main_root"
    _section_worktrees "$main_root"
    _section_open_tasks "$main_root"
    _section_inflight_background "$main_root"
    _section_active_plan "$main_root"
    _section_needs_you "$main_root"
    _section_scratchpad "$main_root"
  } > "$out"
}

# ============================================================
# Live entry path
# ============================================================
_run_live() {
  local transcript="${1:-}"
  if [ -z "$transcript" ]; then
    echo "$SCRIPT_NAME: usage: $SCRIPT_NAME <transcript-path>" >&2
    exit 1
  fi

  local session_id main_root out_dir out
  session_id="$(_derive_session_id "$transcript")"
  main_root="$(_main_root)"
  out_dir="$(_handoff_dir)"
  mkdir -p "$out_dir" 2>/dev/null || true
  out="$out_dir/${session_id}.md"

  _build_snapshot "$transcript" "$session_id" "$main_root" "$out"

  echo "$SCRIPT_NAME: wrote $out"
  exit 0
}

# ============================================================
# Self-test
# ============================================================
_self_test() {
  local pass=0 fail=0
  local tmp
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t sessionsnap)"

  export HARNESS_SELFTEST=1
  export HARNESS_SELFTEST_DIR="$tmp/sandbox"
  mkdir -p "$HARNESS_SELFTEST_DIR"

  # ---- fixture repo (a real git repo so git-state sections have real data) ----
  local repo="$tmp/fixture-repo"
  mkdir -p "$repo/docs/plans"
  ( cd "$repo" && git init -q . \
      && git config user.email "t@example.test" && git config user.name "T" \
      && echo "hello" > README.md && git add README.md && git commit -q -m init ) >/dev/null 2>&1
  echo "uncommitted change" >> "$repo/README.md"

  cat > "$repo/docs/plans/fixture-plan.md" <<'PLAN'
# Fixture plan

Status: ACTIVE

- [x] Task one done
- [ ] Task two — the specific next action
- [ ] Task three
PLAN

  cat > "$repo/NEEDS-YOU.md" <<'NY'
# NEEDS-YOU

## Awaiting your decision
- Something pending
NY

  cat > "$repo/SCRATCHPAD.md" <<'SP'
# Scratchpad
Current state: building E.9.
SP

  mkdir -p "$repo/.claude/state/spawned-task-results"
  echo '{"task_id":"t1","exit_status":"ok"}' > "$repo/.claude/state/spawned-task-results/t1.json"
  echo '{"task_id":"t2","exit_status":"ok"}' > "$repo/.claude/state/spawned-task-results/t2.json"
  : > "$repo/.claude/state/spawned-task-results/t2.json.acked"

  mkdir -p "$repo/.claude/state/orchestrator"
  echo '{"open":true}' > "$repo/.claude/state/orchestrator/queue.json"

  # fixture transcript with a session_id line
  local transcript="$tmp/sess-fixture.jsonl"
  printf '{"type":"user","session_id":"sess-fixture-123","message":{"role":"user","content":"hi"}}\n' > "$transcript"
  printf '{"type":"assistant","session_id":"sess-fixture-123","message":{"role":"assistant","usage":{"input_tokens":2,"cache_read_input_tokens":100}}}\n' >> "$transcript"

  local out="$HARNESS_SELFTEST_DIR/state/session-handoff/sess-fixture-123.md"

  # T1 — basic run: file created, non-empty.
  _build_snapshot "$transcript" "sess-fixture-123" "$repo" "$out"
  if [ -s "$out" ]; then
    echo "  T1 snapshot file created + non-empty: PASS"; pass=$((pass+1))
  else
    echo "  T1 snapshot file created + non-empty: FAIL"; fail=$((fail+1))
  fi

  # T2 — mechanical members of category (3): branch + HEAD + status present.
  if grep -q '^- Branch:' "$out" && grep -q '^- HEAD:' "$out" && grep -q 'Status (`git status' "$out"; then
    echo "  T2 category-3 git branch/HEAD/status present: PASS"; pass=$((pass+1))
  else
    echo "  T2 category-3 git branch/HEAD/status present: FAIL"; fail=$((fail+1))
  fi

  # T3 — in-flight background: t1 (unacked) listed, t2 (acked) NOT listed.
  if grep -q 'task-id=`t1`' "$out" && ! grep -q 'task-id=`t2`' "$out"; then
    echo "  T3 in-flight background ids: unacked shown, acked excluded: PASS"; pass=$((pass+1))
  else
    echo "  T3 in-flight background ids: unacked shown, acked excluded: FAIL"; fail=$((fail+1))
  fi

  # T4 — ACTIVE plan + unchecked tasks + specific next action (category 3's
  # "next action" member) present.
  if grep -q 'fixture-plan.md' "$out" && grep -q 'Unchecked tasks: 2' "$out" && grep -q 'Task two' "$out"; then
    echo "  T4 ACTIVE plan + unchecked count + next action: PASS"; pass=$((pass+1))
  else
    echo "  T4 ACTIVE plan + unchecked count + next action: FAIL"; fail=$((fail+1))
  fi

  # T5 — category (5) mechanical half: NEEDS-YOU content present.
  if grep -q 'Something pending' "$out"; then
    echo "  T5 category-5 NEEDS-YOU content present: PASS"; pass=$((pass+1))
  else
    echo "  T5 category-5 NEEDS-YOU content present: FAIL"; fail=$((fail+1))
  fi

  # T6 — SCRATCHPAD freshness: fresh file (just written) is NOT copied in verbatim.
  if grep -q 'Fresh (mtime' "$out" && ! grep -q 'Current state: building E.9' "$out"; then
    echo "  T6 fresh SCRATCHPAD not copied in: PASS"; pass=$((pass+1))
  else
    echo "  T6 fresh SCRATCHPAD not copied in: FAIL"; fail=$((fail+1))
  fi

  # T7 — SCRATCHPAD staleness: backdate mtime >30min -> full content copied in.
  local old_epoch
  old_epoch=$(( $(date +%s) - 3600 ))
  if command -v touch >/dev/null 2>&1; then
    touch -d "@${old_epoch}" "$repo/SCRATCHPAD.md" 2>/dev/null || touch -t "$(date -d "@${old_epoch}" +%Y%m%d%H%M.%S 2>/dev/null)" "$repo/SCRATCHPAD.md" 2>/dev/null || true
  fi
  local out2="$HARNESS_SELFTEST_DIR/state/session-handoff/sess-stale.md"
  _build_snapshot "$transcript" "sess-stale" "$repo" "$out2"
  if grep -q 'STALE' "$out2" && grep -q 'Current state: building E.9' "$out2"; then
    echo "  T7 stale SCRATCHPAD (>30min) copied in verbatim: PASS"; pass=$((pass+1))
  else
    echo "  T7 stale SCRATCHPAD (>30min) copied in verbatim: FAIL"; fail=$((fail+1))
  fi

  # T8 — idempotent: re-running for the SAME session-id overwrites, no
  # duplication (file size stable across two identical runs; no doubled
  # sections).
  _build_snapshot "$transcript" "sess-fixture-123" "$repo" "$out"
  local branch_count
  branch_count=$(grep -c '^- Branch:' "$out")
  if [ "$branch_count" -eq 1 ]; then
    echo "  T8 idempotent re-run (overwrite, no duplication): PASS"; pass=$((pass+1))
  else
    echo "  T8 idempotent re-run (overwrite, no duplication): FAIL (branch_count=$branch_count)"; fail=$((fail+1))
  fi

  # T9 — session-id derivation from transcript content (authoritative over
  # basename when they disagree).
  local transcript2="$tmp/different-name.jsonl"
  printf '{"type":"assistant","session_id":"sess-real-id","message":{}}\n' > "$transcript2"
  local derived
  derived="$(_derive_session_id "$transcript2")"
  if [ "$derived" = "sess-real-id" ]; then
    echo "  T9 session-id derived from transcript content: PASS"; pass=$((pass+1))
  else
    echo "  T9 session-id derived from transcript content: FAIL (got: $derived)"; fail=$((fail+1))
  fi

  # T10 — missing transcript / no session_id lines -> falls back to basename,
  # never crashes.
  local transcript3="$tmp/sess-basename-fallback.jsonl"
  printf 'not json\n' > "$transcript3"
  derived="$(_derive_session_id "$transcript3")"
  if [ "$derived" = "sess-basename-fallback" ]; then
    echo "  T10 fallback to basename on unparseable transcript: PASS"; pass=$((pass+1))
  else
    echo "  T10 fallback to basename on unparseable transcript: FAIL (got: $derived)"; fail=$((fail+1))
  fi

  # T11 — no ACTIVE plan -> honest "not found" line, no crash.
  local repo_noplan="$tmp/repo-noplan"
  mkdir -p "$repo_noplan/docs/plans"
  ( cd "$repo_noplan" && git init -q . && git config user.email "t@example.test" && git config user.name "T" \
      && echo x > f && git add f && git commit -q -m init ) >/dev/null 2>&1
  local out3="$HARNESS_SELFTEST_DIR/state/session-handoff/sess-noplan.md"
  _build_snapshot "$transcript" "sess-noplan" "$repo_noplan" "$out3"
  if grep -q 'no ACTIVE plan found' "$out3"; then
    echo "  T11 no ACTIVE plan -> honest absence line: PASS"; pass=$((pass+1))
  else
    echo "  T11 no ACTIVE plan -> honest absence line: FAIL"; fail=$((fail+1))
  fi

  # T12 — worktree list section present and non-crashing.
  if grep -q '## 3b. Worktrees' "$out"; then
    echo "  T12 worktree list section present: PASS"; pass=$((pass+1))
  else
    echo "  T12 worktree list section present: FAIL"; fail=$((fail+1))
  fi

  # T13 — sandbox isolation: production ~/.claude/state/session-handoff is
  # never touched by self-test runs (this test only asserts about ITS OWN
  # output path, i.e. HARNESS_SELFTEST_DIR-prefixed, never $HOME directly).
  if [[ "$out" == "$HARNESS_SELFTEST_DIR"* ]]; then
    echo "  T13 snapshot output sandboxed under HARNESS_SELFTEST_DIR: PASS"; pass=$((pass+1))
  else
    echo "  T13 snapshot output sandboxed under HARNESS_SELFTEST_DIR: FAIL (out=$out)"; fail=$((fail+1))
  fi

  rm -rf "$tmp" 2>/dev/null
  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return "$fail"
}

# ============================================================
# Entry point
# ============================================================
case "${1:-}" in
  --self-test) _self_test; exit $? ;;
  -h|--help)
    cat <<USAGE >&2
session-snapshot.sh <transcript-path> — write a mechanical session-handoff
snapshot to ~/.claude/state/session-handoff/<session-id>.md.

  session-snapshot.sh <transcript-path>   Write/overwrite the snapshot.
  session-snapshot.sh --self-test         Run self-test suite.
USAGE
    exit 2
    ;;
  "") _run_live ;;
  *) _run_live "$1" ;;
esac
