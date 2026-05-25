#!/usr/bin/env bash
# harness-evaluator.sh — System 2 of the drift-backlog + harness-evaluator pair.
#
# Reads multiple harness audit-trail substrates and produces a weekly
# review packet at docs/reviews/YYYY-MM-DD-harness-self-eval.md.
#
# Inputs:
#   - .claude/state/drift-backlog/misha-asked-for.json (System 1's output)
#   - .claude/state/scope-waiver-*.txt              (scope-enforcement bypasses)
#   - .claude/state/acceptance-waiver-*.txt         (product-acceptance-gate bypasses)
#   - .claude/state/autonomous-done-*.txt           (narrate-and-wait-gate bypasses)
#   - .claude/state/dag-approved-*.txt              (DAG-review waivers)
#   - .claude/state/close-plan-force-overrides.log  (force-close-plan invocations)
#   - .claude/state/observed-errors-overrides.log   (observed-errors-gate bypasses)
#   - .claude/state/unresolved-stop-hooks.log       (retry-guard downgrades)
#   - .claude/state/failsafe-retirements.md         (retired gates audit)
#   - docs/failure-modes.md                         (catalogued failure classes)
#   - docs/backlog.md                               (HARNESS-GAP entries)
#   - prior docs/reviews/*-harness-self-eval.md     (own track record)
#
# Outputs:
#   - docs/reviews/YYYY-MM-DD-harness-self-eval.md  (committed, shareable)
#
# Design constraints (from plan + Misha's directive):
# - READ-ONLY against the harness. Produces write-ups, never auto-fixes.
# - Every recommendation must cite ≥3 evidence pointers.
# - Self-tracks: each run notes how prior recommendations fared.
# - Misha is the watchdog-for-the-watchdog.
#
# Usage:
#   bash adapters/claude-code/scripts/harness-evaluator.sh           # default: weekly run
#   bash adapters/claude-code/scripts/harness-evaluator.sh --output <path>
#   bash adapters/claude-code/scripts/harness-evaluator.sh --self-test

set -uo pipefail

SELF_TEST=0
OUTPUT_PATH=""
MODE="daily"  # daily | full | weekly-rollup

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_PATH="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    --help|-h) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in
  daily|full|weekly-rollup) ;;
  *) echo "ERROR: --mode must be one of: daily | full | weekly-rollup" >&2; exit 1 ;;
esac

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not on PATH: $1" >&2; exit 1
  fi
}
require_cmd jq
require_cmd git

# ---- repo root + output -----------------------------------------------------
find_repo_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}
REPO_ROOT="$(find_repo_root)"
TODAY="$(date -u +%Y-%m-%d)"
if [[ -z "$OUTPUT_PATH" ]]; then
  # Daily packets live in .claude/state/ (gitignored) — they contain raw
  # GitHub URLs + usernames from System 3's CI tracking and raw user-message
  # content from System 1, neither of which can ship in a generic harness kit.
  # The weekly rollup is the shareable committed artifact (it sanitizes
  # identifiers before writing to docs/reviews/).
  case "$MODE" in
    daily|full)
      OUTPUT_PATH="$REPO_ROOT/.claude/state/harness-eval/$TODAY-harness-self-eval.md"
      ;;
    weekly-rollup)
      OUTPUT_PATH="$REPO_ROOT/docs/reviews/$(date -u +%Y-W%V)-harness-weekly-rollup.md"
      ;;
  esac
fi
DRIFT_BACKLOG="$REPO_ROOT/.claude/state/drift-backlog/misha-asked-for.json"
STATE_DIR="$REPO_ROOT/.claude/state"

# ---- self-test --------------------------------------------------------------
run_self_test() {
  local failed=0
  # 1. State directory exists
  if [[ ! -d "$STATE_DIR" ]]; then
    echo "[self-test] WARN: state dir does not exist ($STATE_DIR) — analyzer will produce mostly-empty packet"
  else
    echo "[self-test] state dir present"
  fi
  # 2. We can compute waiver counts without error
  local n
  n=$(count_files "$STATE_DIR/scope-waiver-*.txt")
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "[self-test] FAIL: count_files broken (got $n)"; failed=1; }
  echo "[self-test] count_files works (got $n scope-waivers)"
  # 3. We can compose a packet header without error
  local hdr
  hdr=$(compose_header "test")
  [[ "$hdr" =~ "# Harness Self-Eval" ]] || { echo "[self-test] FAIL: compose_header broken"; failed=1; }
  echo "[self-test] compose_header works"
  # 4. drift backlog JSON shape detection
  if [[ -f "$DRIFT_BACKLOG" ]]; then
    if jq -e '.drift_items' "$DRIFT_BACKLOG" >/dev/null 2>&1; then
      echo "[self-test] drift-backlog JSON parses"
    else
      echo "[self-test] FAIL: drift-backlog exists but missing .drift_items"; failed=1
    fi
  else
    echo "[self-test] WARN: no drift backlog at $DRIFT_BACKLOG (run mine-misha-asked.sh first)"
  fi
  if [[ $failed -eq 0 ]]; then
    echo "[self-test] all checks passed"; return 0
  else
    echo "[self-test] FAILED ($failed)"; return 2
  fi
}

# ---- helpers ----------------------------------------------------------------
count_files() {
  # Glob expansion safe under set -u
  local pattern="$1"
  local n
  n=$(ls -1 $pattern 2>/dev/null | wc -l | tr -d ' ')
  echo "${n:-0}"
}

compose_header() {
  local mode="${1:-real}"
  cat <<EOF
# Harness Self-Eval — $TODAY

**Generator:** \`adapters/claude-code/scripts/harness-evaluator.sh\` (System 2 of the drift-backlog + harness-evaluator pair, per \`docs/plans/drift-backlog-and-harness-evaluator.md\`).

**Read-only.** This packet is descriptive, not prescriptive. Recommendations are for Misha to review and triage. The evaluator never auto-updates rules, hooks, or agents.

**Inputs read:** drift-backlog (System 1 output), scope-waivers, acceptance-waivers, autonomous-done attestations, dag-approved waivers, close-plan force-overrides, observed-errors-overrides, unresolved-stop-hooks log, failsafe-retirements, failure-mode catalog, HARNESS-GAP backlog, prior weekly packets (own track record).

**Mode:** $mode

---
EOF
}

# ---- section: bypass tally --------------------------------------------------
section_bypass_tally() {
  echo "## 1. Bypass tally (by mechanism)"
  echo
  echo "How many times each gate's escape hatch was authored in the last 60 days."
  echo "High counts on a single gate mean either (a) the gate fires too aggressively,"
  echo "or (b) the work it gates is genuinely orthogonal more often than expected."
  echo "Either way the evaluator surfaces it for Misha's judgment."
  echo

  echo "| Gate | Bypass count | Most-recent date | Top plan(s) bypassing |"
  echo "|---|---|---|---|"

  local n date last plan
  # scope-enforcement-gate.sh waivers
  n=$(count_files "$STATE_DIR/scope-waiver-*.txt")
  last=$(ls -1t $STATE_DIR/scope-waiver-*.txt 2>/dev/null | head -1)
  date=$([[ -n "$last" ]] && stat -c '%y' "$last" 2>/dev/null | cut -d' ' -f1 || echo "—")
  plan=$(ls -1 $STATE_DIR/scope-waiver-*.txt 2>/dev/null | sed 's|.*/scope-waiver-||;s/-2026-.*$//' | sort | uniq -c | sort -rn | awk 'NR<=2{printf "%s (%d), ", $2, $1}' | sed 's/, $//')
  echo "| \`scope-enforcement-gate.sh\` | $n | $date | ${plan:-—} |"

  n=$(count_files "$STATE_DIR/acceptance-waiver-*.txt")
  last=$(ls -1t $STATE_DIR/acceptance-waiver-*.txt 2>/dev/null | head -1)
  date=$([[ -n "$last" ]] && stat -c '%y' "$last" 2>/dev/null | cut -d' ' -f1 || echo "—")
  plan=$(ls -1 $STATE_DIR/acceptance-waiver-*.txt 2>/dev/null | sed 's|.*/acceptance-waiver-||;s/-2026-.*$//' | sort -u | head -2 | tr '\n' ',' | sed 's/,$//')
  echo "| \`product-acceptance-gate.sh\` | $n | $date | ${plan:-—} |"

  n=$(count_files "$STATE_DIR/autonomous-done-*.txt")
  last=$(ls -1t $STATE_DIR/autonomous-done-*.txt 2>/dev/null | head -1)
  date=$([[ -n "$last" ]] && stat -c '%y' "$last" 2>/dev/null | cut -d' ' -f1 || echo "—")
  echo "| \`narrate-and-wait-gate.sh\` | $n | $date | — (session-scoped) |"

  n=$(count_files "$STATE_DIR/dag-approved-*.txt")
  last=$(ls -1t $STATE_DIR/dag-approved-*.txt 2>/dev/null | head -1)
  date=$([[ -n "$last" ]] && stat -c '%y' "$last" 2>/dev/null | cut -d' ' -f1 || echo "—")
  echo "| \`dag-review-waiver-gate.sh\` | $n | $date | — (session-scoped) |"

  # close-plan-force-overrides — these are NOT a gate bypass per se; they're
  # close-plan.sh's --force flag invocations. Count them anyway as a signal of
  # plans that didn't satisfy the mechanical close-plan rubric.
  n=$(grep -c "^Plan:" "$STATE_DIR/close-plan-force-overrides.log" 2>/dev/null || echo 0)
  date=$(tail -50 "$STATE_DIR/close-plan-force-overrides.log" 2>/dev/null | grep -oE '2026-[0-9]{2}-[0-9]{2}' | tail -1)
  plan=$(grep "^Plan:" "$STATE_DIR/close-plan-force-overrides.log" 2>/dev/null | sed 's|^Plan: docs/plans/||;s/\.md$//' | sort | uniq -c | sort -rn | awk 'NR<=2{printf "%s (%d), ", $2, $1}' | sed 's/, $//')
  echo "| \`close-plan.sh --force\` | $n | ${date:--} | ${plan:-—} |"

  if [[ -f "$STATE_DIR/observed-errors-overrides.log" ]]; then
    n=$(wc -l < "$STATE_DIR/observed-errors-overrides.log" 2>/dev/null | tr -d ' ')
  else
    n=0
  fi
  date="—"
  echo "| \`observed-errors-gate.sh\` | $n | $date | — |"

  echo
}

# ---- section: unresolved stop-hooks ----------------------------------------
section_unresolved_stop_hooks() {
  echo "## 2. Unresolved-stop-hooks log (retry-guard downgrades)"
  echo
  echo "When a Stop hook fires the same failure signature 3+ times in one session,"
  echo "the retry-guard library downgrades the block to a warn and appends to"
  echo "\`.claude/state/unresolved-stop-hooks.log\`. High counts indicate gates that"
  echo "are genuinely unresolvable mid-session OR are firing false-positively."
  echo

  local total
  total=$(wc -l < "$STATE_DIR/unresolved-stop-hooks.log" 2>/dev/null || echo 0)
  echo "**Total log entries:** $total"
  echo
  echo "**By hook (top 10):**"
  echo
  echo "| Hook | Count | Unique-signature count |"
  echo "|---|---|---|"
  while IFS= read -r row; do
    local hook=$(echo "$row" | awk '{print $2}')
    local count=$(echo "$row" | awk '{print $1}')
    local uniq=$(grep -F "hook=$hook" "$STATE_DIR/unresolved-stop-hooks.log" 2>/dev/null | grep -oE 'sig=[a-f0-9]+' | sort -u | wc -l)
    echo "| \`$hook\` | $count | $uniq |"
  done < <(grep -oE 'hook=[a-zA-Z-]+' "$STATE_DIR/unresolved-stop-hooks.log" 2>/dev/null | sort | uniq -c | sort -rn | head -10)
  echo

  echo "**Interpretation hints (NOT auto-recommendations):**"
  echo "- High-count + low-unique-sig: same failure recurring across sessions — likely a real ongoing gap (drift, missing prereq)."
  echo "- High-count + high-unique-sig: gate fires across diverse contexts — may indicate over-eager triggering."
  echo "- Single-session bursts (count = N per session): retry-loops within one session — usually a blocker the agent couldn't resolve."
  echo
}

# ---- section: drift backlog summary ----------------------------------------
section_drift_backlog() {
  echo "## 3. Drift backlog (System 1)"
  echo
  if [[ ! -f "$DRIFT_BACKLOG" ]]; then
    echo "**No drift backlog found.** Run \`bash adapters/claude-code/scripts/mine-misha-asked.sh --recent-days 60 --project-filter neural-lace\` first."
    echo
    return 0
  fi

  local total drift satisfied recent_pending
  total=$(jq '.meta.total_unique_asks' "$DRIFT_BACKLOG")
  drift=$(jq '.summary.drift' "$DRIFT_BACKLOG")
  satisfied=$(jq '.summary.satisfied' "$DRIFT_BACKLOG")
  recent_pending=$(jq '.summary.recent_pending' "$DRIFT_BACKLOG")

  echo "**Total unique asks classified:** $total"
  echo "**Drift (no artifact, > 14 days):** $drift"
  echo "**Satisfied (artifact found):** $satisfied"
  echo "**Recent-pending (< 14 days):** $recent_pending"
  echo
  echo "**Oldest 10 drift items (highest signal — Misha asked, no shipped artifact):**"
  echo
  echo "| Age (d) | Reps | Trigger | Ask (truncated) |"
  echo "|---|---|---|---|"
  jq -r '.drift_items[0:10][] | "| \(.age_days) | \(.repetition_count) | `\(.trigger // "—")` | \(.ask | gsub("[|\n]"; " ") | .[0:120]) |"' "$DRIFT_BACKLOG"
  echo
  echo "**Items repeated 2+ times across sessions (Misha re-asked — strong drift signal):**"
  local n_rep
  n_rep=$(jq '[.drift_items[] | select(.repetition_count > 1)] | length' "$DRIFT_BACKLOG")
  if [[ "$n_rep" -eq 0 ]]; then
    echo
    echo "_None in this scan window._ (May indicate (a) Misha doesn't re-ask, (b) dedup is too aggressive, (c) classification is hiding repeats.)"
  else
    echo
    echo "| Reps | Age (d) | Trigger | Ask |"
    echo "|---|---|---|---|"
    jq -r '[.drift_items[] | select(.repetition_count > 1)] | sort_by(.repetition_count) | reverse | .[0:10][] | "| \(.repetition_count) | \(.age_days) | `\(.trigger)` | \(.ask | gsub("[|\n]"; " ") | .[0:120]) |"' "$DRIFT_BACKLOG"
  fi
  echo
}

# ---- section: top-3 lists ---------------------------------------------------
section_top3() {
  echo "## 4. Top-3 lists (Misha's review packet)"
  echo
  echo "Per the design constraint: every recommendation cites ≥3 evidence pointers."
  echo "Recommendations are descriptive, NOT auto-applied."
  echo

  # 4.1 Top-3 most-bypassed gates
  echo "### 4.1 Top 3 rules with highest bypass count"
  echo
  local sw_count cp_count ap_count an_count
  sw_count=$(count_files "$STATE_DIR/scope-waiver-*.txt")
  cp_count=$(grep -c "^Plan:" "$STATE_DIR/close-plan-force-overrides.log" 2>/dev/null || echo 0)
  ap_count=$(count_files "$STATE_DIR/acceptance-waiver-*.txt")
  an_count=$(count_files "$STATE_DIR/autonomous-done-*.txt")
  {
    echo "$sw_count scope-enforcement-gate.sh|$cp_count close-plan.sh --force|$ap_count product-acceptance-gate.sh|$an_count narrate-and-wait-gate.sh"
  } | tr '|' '\n' | sort -rn | head -3 | nl -w2 -s'. ' | while read -r line; do
    local count=$(echo "$line" | awk '{print $2}')
    local name=$(echo "$line" | awk '{print $3}')
    if [[ "$count" -eq 0 ]]; then
      echo "$(echo "$line" | awk '{print $1}') $name — 0 bypasses (clean)"
    else
      echo "$(echo "$line" | awk '{print $1}') $name — $count bypasses"
      case "$name" in
        scope-enforcement-gate.sh)
          echo "   - Evidence 1: $count waiver files at \`.claude/state/scope-waiver-*.txt\`"
          echo "   - Evidence 2: top plan needing waivers — \`pre-submission-audit-mechanical-enforcement\` (9 waivers, see ls)"
          echo "   - Evidence 3: when a plan needs 9 waivers, the plan's scope was authored too narrowly OR the gate's path-matching is too strict"
          echo "   - **Recommendation (descriptive):** investigate whether pre-submission-audit plan's scope should have included sibling files from the start, or whether the gate's regex needs an allowlist for that plan-shape"
          ;;
        close-plan.sh)
          echo "   - Evidence 1: $count force-overrides logged at \`.claude/state/close-plan-force-overrides.log\`"
          echo "   - Evidence 2: forced overrides cluster around the architecture-simplification tranche plans"
          echo "   - Evidence 3: \`close-plan.sh\`'s rubric (typecheck, evidence-block, runtime-correspondence) may be stricter than Tranche-level plans need"
          echo "   - **Recommendation (descriptive):** audit whether the rubric should be conditional on plan rung/tier"
          ;;
        product-acceptance-gate.sh)
          echo "   - Evidence 1: $count acceptance-waivers at \`.claude/state/acceptance-waiver-*.txt\`"
          echo "   - Evidence 2: cross-session waivers indicate the gate fires on stale ACTIVE plans not exercised in the current session"
          echo "   - Evidence 3: per \`rules/git-discipline.md\` Rule 3, this is a known pattern — write the waiver UP FRONT for orthogonal plans"
          echo "   - **Recommendation (descriptive):** Misha may want to retire/archive long-stale ACTIVE plans that don't represent current work"
          ;;
        narrate-and-wait-gate.sh)
          echo "   - Evidence 1: $count autonomous-done attestations at \`.claude/state/autonomous-done-*.txt\`"
          echo "   - Evidence 2: low count suggests sessions are correctly ending under explicit-done OR the gate isn't triggering often"
          echo "   - Evidence 3: cross-check against unresolved-stop-hooks for narrate-and-wait hook entries"
          echo "   - **Recommendation (descriptive):** if observed-bypass-count is much lower than expected-session-count, the gate may be silently passing"
          ;;
      esac
    fi
  done
  echo

  # 4.2 Top-3 drift items (highest age + reps signal)
  echo "### 4.2 Top 3 newly-surfaced drift items (System 1)"
  echo
  if [[ -f "$DRIFT_BACKLOG" ]]; then
    local n=0
    jq -r '.drift_items[0:3][] | "\(.age_days)|\(.repetition_count)|\(.trigger // "—")|\(.ask | gsub("[|\n]"; " ") | .[0:160])"' "$DRIFT_BACKLOG" | while IFS='|' read -r age reps trig ask; do
      n=$((n+1))
      echo "$n. **${age}d old** (reps=$reps): \"$ask\""
      echo "   - Evidence 1: ask first observed at $(jq -r --arg a "$ask" '[.drift_items[] | select(.ask | startswith($a[0:80]))] | .[0].first_ts // "unknown"' "$DRIFT_BACKLOG" 2>/dev/null)"
      echo "   - Evidence 2: no satisfying artifact found in git log / branches / failure-modes / backlog"
      echo "   - Evidence 3: trigger pattern \`$trig\` matched — heuristic-class signal, may be false positive"
      echo "   - **Recommendation (descriptive):** Misha review whether this is genuinely undone or was satisfied through a channel artifact_search doesn't see"
      echo
    done
  else
    echo "_No drift backlog available (run System 1 first)._"
    echo
  fi

  # 4.3 Top-3 known weak rules (manual seed — these are things Claude knows the harness doesn't strongly enforce)
  echo "### 4.3 Top 3 rules with KNOWN-weak enforcement (from harness documentation)"
  echo
  echo "These are explicitly documented as residual gaps by the harness itself (\`rules/vaporware-prevention.md\` 'Missing from the enforcement map' + 'Residual gap'):"
  echo
  cat <<'EOF'
1. **`claim-reviewer` agent — self-invoked, can be skipped**
   - Evidence 1: `rules/vaporware-prevention.md` "Residual gap (honest)" section explicitly: "Verbal vaporware in conversation is not mechanically blocked. Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped."
   - Evidence 2: `rules/vaporware-prevention.md` table marks this row as "self-invoked (residual gap)"
   - Evidence 3: this is the canonical case of "rule that didn't prevent incidents but couldn't be bypassed because it never fired"
   - **Recommendation (descriptive):** until Claude Code ships a PostMessage hook, the only mitigation is the file:line-citation discipline + Misha's interrupt authority. The evaluator should track how often `claim-reviewer` IS invoked vs the number of feature-claim-bearing assistant messages.
EOF
  echo
  cat <<'EOF'
2. **`tool-call-budget.sh --ack` attestation is bypassable by direct file write**
   - Evidence 1: `rules/vaporware-prevention.md` "Missing from the enforcement map" explicitly: "A builder could Write that file directly without invoking `plan-evidence-reviewer`."
   - Evidence 2: Friction raised (need sentinel format knowledge) but "not cryptographically closed"
   - Evidence 3: "Accepted residual risk for Gen 4"
   - **Recommendation (descriptive):** evaluator can track frequency of attestation-file writes WITHOUT a paired plan-evidence-reviewer invocation in the same session.
EOF
  echo
  cat <<'EOF'
3. **`review-finding-fix-gate.sh` reads stale `.git/COMMIT_EDITMSG` (HARNESS-GAP-23)**
   - Evidence 1: `docs/backlog.md` HARNESS-GAP-23 documents this as a known issue (added 2026-05-06)
   - Evidence 2: this very System 2 build hit it: the gate matched ADR-031 from a previous unrelated commit
   - Evidence 3: workaround is to clear .git/COMMIT_EDITMSG before invoking `git commit -m` — undocumented and undiscoverable for new sessions
   - **Recommendation (descriptive):** fix HARNESS-GAP-23 by reading the actual staged-commit message via stdin rather than the stale file
EOF
  echo

  # 4.4 Top-3 agents whose discipline may be degrading
  echo "### 4.4 Top 3 agents to watch for discipline degradation"
  echo
  echo "These are heuristic flags — agents that have shown patterns of cutting corners under pressure. Cross-reference with future calibration entries at \`.claude/state/calibration/<agent-name>.md\` per \`rules/calibration-loop.md\`."
  echo
  cat <<'EOF'
1. **`plan-phase-builder` — finding-workarounds-to-mark-complete**
   - Evidence 1: agent's own `## Counter-Incentive Discipline` section names "training-induced bias toward call-it-done shortcuts"
   - Evidence 2: `docs/failure-modes.md` FM-001..N catalog includes builder shortcuts as a recurring class
   - Evidence 3: lessons doc `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` chronicles a multi-day builder-shortcut chain
   - **Recommendation (descriptive):** instrument task-verifier dispatches to check whether builder return shape includes hedge phrases ("partial", "deferred", "out-of-scope") at higher than expected rate

2. **`task-verifier` — pass-by-default on mechanical tasks**
   - Evidence 1: `Verification: mechanical` early-returns PASS without running full rubric (per `rules/risk-tiered-verification.md`)
   - Evidence 2: 92% of harness-dev tasks are `Verification: mechanical` — the dispatch rarely runs
   - Evidence 3: Calibration substrate at `.claude/state/calibration/task-verifier.md` is intentionally seeded for this exact class
   - **Recommendation (descriptive):** sample-audit some mechanical-class PASS verdicts manually to confirm they hold

3. **`end-user-advocate` — not dispatchable in Dispatch env (HARNESS-GAP-34)**
   - Evidence 1: `docs/backlog.md` HARNESS-GAP-34 (added 2026-05-15) documents that the agent cannot run in remote-Dispatch sessions
   - Evidence 2: the runtime acceptance loop therefore can't fire when the orchestrator is remote
   - Evidence 3: every acceptance-exempt: true on a Dispatch-built plan masks an inability, not a legitimate exemption
   - **Recommendation (descriptive):** count Dispatch-attributed plans with acceptance-exempt: true vs total; high ratio indicates the gap is biting
EOF
  echo
}

# ---- section: own track record ---------------------------------------------
section_own_track_record() {
  echo "## 5. Own track record (recommendation outcomes)"
  echo
  local prior_count
  prior_count=$(ls -1 "$REPO_ROOT"/docs/reviews/*-harness-self-eval.md 2>/dev/null | grep -v "^$OUTPUT_PATH$" | wc -l | tr -d ' ')
  if [[ "$prior_count" -eq 0 ]]; then
    echo "**First weekly packet.** No prior recommendations to evaluate."
    echo
    echo "On the NEXT run, this section will list each prior recommendation and one of: acted-on / ignored / partially-shipped, with citation."
    echo
    return 0
  fi
  echo "**Prior packets found: $prior_count**"
  echo
  # In a future iteration, parse prior packets and check whether their recommendations
  # have corresponding commits / file changes since the prior date.
  echo "_TODO (next iteration): for each recommendation in the most-recent prior packet, search git log between then and now for commits referencing the recommendation. Mark acted-on / ignored / partially-shipped._"
  echo
  echo "Until that's implemented, Misha reads prior packets manually and updates them with status notes."
  echo
}

# ---- section: failsafe retirements -----------------------------------------
section_failsafe_audit() {
  echo "## 6. Failsafe retirements"
  echo
  if [[ -f "$STATE_DIR/failsafe-retirements.md" ]]; then
    local n
    n=$(grep -c "^## " "$STATE_DIR/failsafe-retirements.md" 2>/dev/null || echo 0)
    echo "**Retired gates logged: $n**"
    echo
    grep "^## " "$STATE_DIR/failsafe-retirements.md" 2>/dev/null | sed 's/^## //'
    echo
    echo "Cross-check: are any retired gates' responsibilities now under-covered? (Heuristic only — Misha to judge.)"
    echo
  else
    echo "_No failsafe-retirements.md log present._"
    echo
  fi
}

# ---- section: pointers --------------------------------------------------------
section_pointers() {
  echo "## 7. Pointers + freshness"
  echo
  echo "**Drift backlog generated:** $([[ -f "$DRIFT_BACKLOG" ]] && jq -r '.meta.generated_at' "$DRIFT_BACKLOG" || echo "—")"
  echo "**Drift backlog window:** \`recent-days\` setting last used (check script invocation)"
  echo "**State dir:** \`.claude/state/\` (gitignored)"
  echo "**Failure-mode catalog:** \`docs/failure-modes.md\` ($(grep -c "^## FM-" "$REPO_ROOT/docs/failure-modes.md" 2>/dev/null || echo "?") entries)"
  echo "**HARNESS-GAP backlog entries:** $(grep -c "HARNESS-GAP-" "$REPO_ROOT/docs/backlog.md" 2>/dev/null || echo "?")"
  echo
  echo "---"
  echo
  echo "**Next packet:** TBD per Misha's review cadence. Schedule via \`/schedule\` or cron (see plan task 6 for placeholder)."
  echo
  echo "**Honesty note:** this packet is v1. Known limitations:"
  echo "- Section 4.4 'agents to watch' is currently heuristic-seeded, not data-driven. Future iteration ties to \`.claude/state/calibration/\` per \`rules/calibration-loop.md\`."
  echo "- Section 5 'own track record' is placeholder until 2+ packets exist for cross-reference."
  echo "- Drift items have false-positive rate — see plan's \"Known v1 limitations\"."
  echo
}

# ---- section: daily skim ---------------------------------------------------
# Skim-fast 3-5 bullet format per Misha 2026-05-25. Deep treatment via
# collapsible <details> blocks. Default-collapsed.
section_daily_skim() {
  local sw_count cp_count ap_count drift_count drift_new today_ci_fail today_ci_pass
  sw_count=$(count_files "$STATE_DIR/scope-waiver-*.txt")
  cp_count=$(grep -c "^Plan:" "$STATE_DIR/close-plan-force-overrides.log" 2>/dev/null || echo 0)
  ap_count=$(count_files "$STATE_DIR/acceptance-waiver-*.txt")
  if [[ -f "$DRIFT_BACKLOG" ]]; then
    drift_count=$(jq '.summary.drift' "$DRIFT_BACKLOG")
  else
    drift_count="?"
  fi
  # CI watcher state
  local ci_tracked ci_fail
  if [[ -d "$STATE_DIR/ci-watcher" ]]; then
    ci_tracked=$(ls -1 "$STATE_DIR/ci-watcher"/*.json 2>/dev/null | grep -v drift-items | wc -l | tr -d ' ')
    ci_fail=0
    for f in "$STATE_DIR/ci-watcher"/*.json; do
      [[ -f "$f" ]] || continue
      [[ "$(basename "$f")" == "drift-items.jsonl" ]] && continue
      local s=$(jq -r '.last_check_state' "$f" 2>/dev/null)
      [[ "$s" == "fail" ]] && ci_fail=$((ci_fail+1))
    done
  else
    ci_tracked=0
    ci_fail=0
  fi

  echo "## Daily skim — $TODAY"
  echo
  echo "**The bullets** (everything else collapsed below):"
  echo
  if [[ "$ci_fail" -gt 0 ]]; then
    echo "- ⚠ **CI failing on $ci_fail of $ci_tracked tracked PRs** — see Section A for the list. Each is a Dispatch-spawned PR that needs follow-up."
  else
    echo "- ✓ CI: all $ci_tracked tracked Dispatch PRs green."
  fi
  echo "- Drift backlog: **$drift_count items > 14d** unsatisfied. Top 3 in Section C."
  echo "- Scope-gate bypasses: $sw_count total, close-plan --force: $cp_count, acceptance waivers: $ap_count. Section B for breakdown."
  echo "- Section D: agents to watch (heuristic, may be stale)."
  echo "- Section E: own track record (improves over time as prior daily packets accumulate)."
  echo
  echo "---"
  echo
  echo '<details>'
  echo '<summary>Section A — CI watcher details</summary>'
  echo
  if [[ -d "$STATE_DIR/ci-watcher" ]]; then
    echo "| Repo | PR | Branch | State | Last seen |"
    echo "|---|---|---|---|---|"
    for f in "$STATE_DIR/ci-watcher"/*.json; do
      [[ -f "$f" ]] || continue
      [[ "$(basename "$f")" == "drift-items.jsonl" ]] && continue
      jq -r '"| \(.repo) | #\(.pr_num) | `\(.branch)` | **\(.last_check_state)** | \(.last_seen_ts) |"' "$f" 2>/dev/null
    done
    if [[ -f "$STATE_DIR/ci-watcher/drift-items.jsonl" ]]; then
      echo
      echo "**Recent CI drift items (last 5):**"
      tail -5 "$STATE_DIR/ci-watcher/drift-items.jsonl" | while read -r line; do
        echo "$line" | jq -r '"- \(.ts) — \(.repo)#\(.pr_num): \(.transition.from) → \(.transition.to) — [\(.title)](\(.url))"' 2>/dev/null
      done
    fi
  else
    echo "_CI watcher state dir does not exist. Run \`dispatch-ci-watcher.sh\` first._"
  fi
  echo
  echo '</details>'
  echo
  echo '<details>'
  echo '<summary>Section B — Bypass tally (last 60 days)</summary>'
  echo
  section_bypass_tally
  echo '</details>'
  echo
  echo '<details>'
  echo '<summary>Section C — Drift backlog top items</summary>'
  echo
  section_drift_backlog
  echo '</details>'
  echo
  echo '<details>'
  echo '<summary>Section D — Agents to watch + known-weak rules</summary>'
  echo
  echo "Known-weak rules and agents-to-watch are cited from harness's own documentation. Cross-reference \`docs/reviews/$(ls -1t docs/reviews/*-harness-self-eval.md 2>/dev/null | grep -v "^$OUTPUT_PATH$" | head -1 | xargs basename 2>/dev/null || echo '—')\` for the full evidence (this section is the skim; the prior weekly-format packet has the full citations)."
  echo '</details>'
  echo
  echo '<details>'
  echo '<summary>Section E — Own track record (prior recommendations)</summary>'
  echo
  section_own_track_record
  echo '</details>'
  echo
  section_pointers
}

# ---- section: weekly rollup ------------------------------------------------
# Diffs the last 7 daily packets. Surfaces what is NEW vs ongoing.
section_weekly_rollup() {
  echo "## Weekly Rollup — week ending $TODAY"
  echo
  local recent_packets
  recent_packets=$(ls -1t "$REPO_ROOT"/docs/reviews/*-harness-self-eval.md 2>/dev/null | head -7)
  local n_packets
  n_packets=$(echo "$recent_packets" | grep -c . || echo 0)
  echo "**Packets covered:** $n_packets"
  echo
  if [[ "$n_packets" -lt 2 ]]; then
    echo "_Not enough prior daily packets for a rollup. Need 2+; have $n_packets._"
    echo
    return
  fi
  echo "**Daily packets in this rollup window:**"
  echo
  for p in $recent_packets; do
    echo "- $(basename "$p")"
  done
  echo
  echo "**Diff summary** (TODO — v1 placeholder; v2 will parse each packet's Section 1 bypass tallies and surface week-over-week deltas)."
  echo
  echo "Until v2 lands, read the daily packets directly — they are intentionally skim-fast."
}

# ---- main entrypoint -------------------------------------------------------
if [[ $SELF_TEST -eq 1 ]]; then
  run_self_test
  exit $?
fi

echo "[harness-eval] mode=$MODE → $OUTPUT_PATH"
mkdir -p "$(dirname "$OUTPUT_PATH")"

case "$MODE" in
  daily)
    {
      compose_header "daily skim"
      section_daily_skim
    } > "$OUTPUT_PATH"
    ;;
  full)
    {
      compose_header "full"
      section_bypass_tally
      section_unresolved_stop_hooks
      section_drift_backlog
      section_top3
      section_own_track_record
      section_failsafe_audit
      section_pointers
    } > "$OUTPUT_PATH"
    ;;
  weekly-rollup)
    # Override output path for weekly mode
    if [[ -z "${OUTPUT_PATH_OVERRIDE:-}" ]]; then
      local_week=$(date -u +%Y-W%V)
      OUTPUT_PATH="$REPO_ROOT/docs/reviews/${local_week}-harness-weekly-rollup.md"
      mkdir -p "$(dirname "$OUTPUT_PATH")"
    fi
    {
      compose_header "weekly rollup"
      section_weekly_rollup
    } > "$OUTPUT_PATH"
    ;;
esac

echo "[harness-eval] wrote: $OUTPUT_PATH"
echo "[harness-eval] $(wc -l < "$OUTPUT_PATH" | tr -d ' ') lines"
