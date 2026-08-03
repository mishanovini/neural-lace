#!/bin/bash
# NEURAL-LACE-BACKLOG-PLAN-ATOMICITY v2 — enforces Rule 1: plan creation absorbs backlog items
#
# Classification: Mechanism (hook-enforced pre-commit blocker)
#
# Enforces the rule from the document-freshness system ("Rule 1 — plan
# creation absorbs backlog items"). When a new `docs/plans/*.md` file is
# added whose header declares `Backlog items absorbed: <non-empty list>`,
# the same commit MUST also stage `docs/backlog.md`. This guarantees that
# items claimed by a plan are deleted from the backlog in the same atomic
# change — you cannot leave a backlog entry dangling once a plan owns it.
#
# BEHAVIOR
#   For every ADDED file matching `docs/plans/<anything>.md` (excluding
#   `-evidence.md` sidecar files):
#     - Read the first 20 lines (header region).
#     - Look for a line matching `^Backlog items absorbed:\s*(.*)$`.
#     - If the captured value is empty, `none`, `[]`, or the field is
#       missing entirely, this plan imposes NO requirement (ALLOW).
#     - Otherwise, this plan absorbs at least one item. Record it.
#   If any added plan absorbs items AND `docs/backlog.md` is NOT staged
#   (any status), BLOCK with a message naming the plans.
#
#   Plan modifications (status M) and deletions (D) do not trigger.
#   Pure renames are treated as ADDs at the destination.
#   Sidecar evidence files (`*-evidence.md`) are ignored.
#
# v2 (R3.4 Gate Philosophy Law retrofit, Stage 0b): structured block message
# (WHAT/WHY/FIX/ESCAPE fields, doctor-lintable), a `--check` read-only
# pre-flight mode sharing the SAME decision logic as the enforce path
# (`_bpa_collect_and_decide` — one function, no drift possible between
# "would this block" and "does this block"), and a cheap relevance
# pre-filter (bail before the name-status/rename parse when no staged path
# is under docs/plans/). Decision semantics are UNCHANGED — the 5 pre-
# existing self-test scenarios (a-e) still assert the same exit codes.
#
# INVOCATION
#   1. Pre-commit chain: backlog-plan-atomicity.sh
#                        (no args — reads `git diff --cached --name-status -z`)
#   2. Pre-flight check:  backlog-plan-atomicity.sh --check
#                        Read-only "would this block" verdict — runs the
#                        identical decision logic against the CURRENTLY
#                        STAGED index without side effects. Use before
#                        committing to see the verdict early (guide, not
#                        wall). Exit code mirrors the verdict (0 = would
#                        pass, 1 = would block); nothing is actually
#                        blocked by --check itself.
#   3. Self-test:        backlog-plan-atomicity.sh --self-test
#
# EXIT CODES
#   0 — allowed (enforce) / would-pass (--check)
#   1 — blocked (enforce) / would-block (--check) — plan absorbs items
#       without staging docs/backlog.md
#
# Wired into the pre-commit chain via pre-commit-gate.sh's FRESHNESS_GATES
# array (adapters/claude-code/hooks/pre-commit-gate.sh).

set -u

# ---------- self-test ----------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
    git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
    git config user.email "selftest@example.test"
    git config user.name "selftest"
    mkdir -p docs/plans
    echo "placeholder" > README.md
    printf '# Backlog\n\nLast updated: 2026-04-18\n\n- [x] Item X\n- [ ] Item Y\n' > docs/backlog.md
    git add README.md docs/backlog.md
    git commit -q -m "init" >/dev/null 2>&1
  ) || { echo "self-test: FAIL — repo init failed" >&2; exit 1; }

  run_case() {
    local label="$1"; local expected_rc="$2"; local setup_fn="$3"
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      rm -f docs/plans/*.md
      git checkout -q -- . 2>/dev/null || true
      $setup_fn
    )
    set +e
    local out
    out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" 2>&1)
    local rc=$?
    set -e
    if [ "$rc" -ne "$expected_rc" ]; then
      echo "self-test: FAIL — case '$label' expected rc=$expected_rc, got rc=$rc" >&2
      echo "  output was:" >&2
      printf '    %s\n' "$out" >&2
      return 1
    fi
    echo "self-test: case '$label' OK (rc=$rc)"
    return 0
  }

  setup_a_plan_absorbs_no_backlog() {
    # Plan absorbs items, backlog NOT staged → BLOCK
    printf '# Plan: Example\nStatus: ACTIVE\nBacklog items absorbed: item-alpha, item-beta\n\nBody.\n' \
      > docs/plans/new-feature.md
    git add docs/plans/new-feature.md
  }

  setup_b_plan_absorbs_none() {
    # Plan with `Backlog items absorbed: none` → ALLOW without backlog stage
    printf '# Plan: Example\nStatus: ACTIVE\nBacklog items absorbed: none\n\nBody.\n' \
      > docs/plans/fresh-feature.md
    git add docs/plans/fresh-feature.md
  }

  setup_c_plan_absorbs_with_backlog() {
    # Plan absorbs items AND backlog staged → ALLOW
    printf '# Plan: Example\nStatus: ACTIVE\nBacklog items absorbed: item-gamma\n\nBody.\n' \
      > docs/plans/another-feature.md
    printf '# Backlog\n\nLast updated: 2026-04-18\n\n- [x] Item X\n' > docs/backlog.md
    git add docs/plans/another-feature.md docs/backlog.md
  }

  setup_d_plan_modify_only() {
    # First commit a plan that absorbs items, then MODIFY it — no backlog needed
    printf '# Plan: Seed\nStatus: ACTIVE\nBacklog items absorbed: item-delta\n\nBody.\n' \
      > docs/plans/seed-plan.md
    printf '# Backlog\n\nLast updated: 2026-04-18\n' > docs/backlog.md
    git add docs/plans/seed-plan.md docs/backlog.md
    git commit -q -m "seed plan" >/dev/null
    # Now just modify the plan body, no backlog change
    printf '# Plan: Seed\nStatus: ACTIVE\nBacklog items absorbed: item-delta\n\nBody v2.\n' \
      > docs/plans/seed-plan.md
    git add docs/plans/seed-plan.md
  }

  setup_e_no_plans_staged() {
    echo "another line" >> README.md
    git add README.md
  }

  # ---- R3.4 Gate Philosophy Law additions: --check parity + message fields ----
  # run_case_check: identical setup/teardown to run_case, but invokes the
  # hook with `--check` and captures output for content assertions (proves
  # --check shares the SAME decision as enforce — no drift possible since
  # both call _bpa_print_block off the same PLANS_ABSORBING computation).
  CHECK_LAST_OUT=""
  run_case_check() {
    local label="$1"; local expected_rc="$2"; local setup_fn="$3"
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      rm -f docs/plans/*.md
      git checkout -q -- . 2>/dev/null || true
      $setup_fn
    )
    set +e
    local out
    out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" --check 2>&1)
    local rc=$?
    set -e
    CHECK_LAST_OUT="$out"
    if [ "$rc" -ne "$expected_rc" ]; then
      echo "self-test: FAIL — case '$label' expected rc=$expected_rc, got rc=$rc" >&2
      echo "  output was:" >&2
      printf '    %s\n' "$out" >&2
      return 1
    fi
    echo "self-test: case '$label' OK (rc=$rc)"
    return 0
  }

  FAIL=0
  run_case "a: plan absorbs without backlog" 1 setup_a_plan_absorbs_no_backlog || FAIL=1

  # h: scenario a's normal (enforce) BLOCKED output must carry the four
  # structured fields the doctor's gate-message lint checks for.
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    rm -f docs/plans/*.md
    git checkout -q -- . 2>/dev/null || true
    setup_a_plan_absorbs_no_backlog
  )
  set +e
  H_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" 2>&1)
  set -e
  H_OK=1
  for marker in "WHAT:" "WHY:" "FIX:" "ESCAPE:"; do
    if [[ "$H_OUT" != *"$marker"* ]]; then
      H_OK=0
      echo "self-test: FAIL (h) — structured block message missing '$marker' field" >&2
    fi
  done
  if [ "$H_OK" -eq 1 ]; then
    echo "self-test: case 'h: structured-message-fields' OK" >&2
  else
    printf '    %s\n' "$H_OUT" >&2
    FAIL=1
  fi

  run_case "b: plan absorbs none"            0 setup_b_plan_absorbs_none       || FAIL=1
  run_case "c: plan absorbs with backlog"    0 setup_c_plan_absorbs_with_backlog || FAIL=1
  run_case "d: plan modify only"             0 setup_d_plan_modify_only        || FAIL=1
  run_case "e: no plans staged"              0 setup_e_no_plans_staged         || FAIL=1

  # f: --check would-block parity with scenario a (same fixture, --check flag)
  run_case_check "f: --check would-block parity" 1 setup_a_plan_absorbs_no_backlog || FAIL=1
  if [[ "$CHECK_LAST_OUT" != *"WOULD BLOCK"* ]]; then
    echo "self-test: FAIL (f) — --check output missing 'WOULD BLOCK' verdict" >&2
    FAIL=1
  fi
  if [[ "$CHECK_LAST_OUT" != *"advisory only"* ]]; then
    echo "self-test: FAIL (f) — --check output missing advisory-only notice" >&2
    FAIL=1
  fi

  # g: --check would-pass parity with scenario c (absorbs + backlog staged)
  run_case_check "g: --check would-pass parity" 0 setup_c_plan_absorbs_with_backlog || FAIL=1
  if [[ "$CHECK_LAST_OUT" != *"would-pass"* ]]; then
    echo "self-test: FAIL (g) — --check clean-fixture output missing would-pass verdict" >&2
    FAIL=1
  fi

  # i: cheap relevance pre-filter — a commit touching no docs/plans/ path at
  # all (scenario e's fixture) must still resolve to would-pass under --check.
  run_case_check "i: --check pre-filter fast-path" 0 setup_e_no_plans_staged || FAIL=1

  if [ "$FAIL" -eq 0 ]; then
    echo "self-test: OK"
    exit 0
  fi
  exit 1
fi

# ---------- --check pre-flight mode (R3.4 Gate Philosophy Law) -----------
# Read-only "would this block" verdict. Same decision logic as enforce
# (below) via the identical staged-file collection + absorption parse —
# there is no second code path to drift out of sync with the real gate.
CHECK_MODE=0
if [ "${1:-}" = "--check" ]; then
  CHECK_MODE=1
fi

# ---------- repo discovery -----------------------------------------------

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi

# ---------- cheap relevance pre-filter ------------------------------------
# This gate ONLY ever fires on an ADDED docs/plans/*.md file. If nothing
# staged touches docs/plans/ at all, the outcome is deterministically
# ALLOW — bail before the heavier name-status + rename-aware token parse
# below (mapfile over null-delimited tokens, per-entry rename handling).
QUICK_PATHS=$(cd "$REPO_ROOT" && git diff --cached --name-only -z --diff-filter=ACMRD 2>/dev/null) || QUICK_PATHS=""
if [ -z "$QUICK_PATHS" ]; then
  if [ "$CHECK_MODE" -eq 1 ]; then
    echo "[backlog-plan-atomicity --check] would-pass (nothing staged)" >&2
  fi
  exit 0
fi
if ! printf '%s' "$QUICK_PATHS" | tr '\0' '\n' | grep -q '^docs/plans/.*\.md$'; then
  if [ "$CHECK_MODE" -eq 1 ]; then
    echo "[backlog-plan-atomicity --check] would-pass (no docs/plans/*.md staged)" >&2
  fi
  exit 0
fi

# ---------- collect staged files -----------------------------------------

STAGED_LIST_TMP=$(mktemp)
trap 'rm -f "$STAGED_LIST_TMP"' EXIT

( cd "$REPO_ROOT" && git diff --cached --name-status -z --diff-filter=ACMRD ) > "$STAGED_LIST_TMP" 2>/dev/null || true

if [ ! -s "$STAGED_LIST_TMP" ]; then
  exit 0
fi

# Read null-delimited tokens
mapfile -d '' -t TOKENS < "$STAGED_LIST_TMP"

HAS_BACKLOG_STAGED=0
ADDED_PLAN_FILES=()

i=0
N=${#TOKENS[@]}
while [ "$i" -lt "$N" ]; do
  status="${TOKENS[$i]}"
  i=$((i + 1))
  [ "$i" -lt "$N" ] || break
  path="${TOKENS[$i]}"
  i=$((i + 1))

  # Renames consume an extra token. For the archival pattern (rename from
  # docs/plans/<file>.md to docs/plans/archive/<file>.md, shipped by the
  # plan-lifecycle.sh hook) we explicitly skip — archived plans are NOT
  # newly absorbing backlog items; the absorption happened at the original
  # plan creation time. For non-archival renames, treat destination as the
  # effective path and treat the entry as an ADD at the destination.
  src_path="$path"
  case "$status" in
    R*)
      if [ "$i" -lt "$N" ]; then
        path="${TOKENS[$i]}"
        i=$((i + 1))
      fi
      # Archival: src under docs/plans/, dst under docs/plans/archive/.
      # Skip — this is the plan-lifecycle.sh self-archival path.
      case "$src_path" in
        docs/plans/*.md)
          case "$path" in
            docs/plans/archive/*.md)
              continue
              ;;
          esac
          ;;
      esac
      status="A"
      ;;
  esac

  # Backlog staged? (any status)
  if [ "$path" = "docs/backlog.md" ]; then
    HAS_BACKLOG_STAGED=1
    continue
  fi

  # Added plan file (skip evidence sidecars)?
  case "$path" in
    docs/plans/*-evidence.md)
      # Evidence sidecar — ignore
      ;;
    docs/plans/*.md)
      if [ "$status" = "A" ]; then
        ADDED_PLAN_FILES+=("$path")
      fi
      ;;
  esac
done

# ---------- inspect each added plan's header ----------------------------

# Returns 0 if the plan absorbs items (non-empty list), 1 if it does not.
plan_absorbs_items() {
  local plan_path="$1"
  local full_path="$REPO_ROOT/$plan_path"
  [ -f "$full_path" ] || return 1

  # Extract the value after `Backlog items absorbed:` in the first 20 lines.
  # Case-insensitive match on the key; value is everything after the colon,
  # trimmed.
  local value
  value=$(head -n 20 "$full_path" \
    | grep -iE '^[[:space:]]*Backlog items absorbed:' \
    | head -n 1 \
    | sed -E 's/^[[:space:]]*[Bb]acklog items absorbed:[[:space:]]*//')

  # Field missing entirely → not absorbing
  if [ -z "${value:-}" ]; then
    return 1
  fi

  # Strip trailing whitespace/newlines
  value="${value%%[[:space:]]}"

  # Normalize to lowercase for comparison
  local lower
  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')

  # Empty, "none", "[]" → not absorbing
  case "$lower" in
    ""|"none"|"[]"|"n/a"|"-")
      return 1
      ;;
  esac

  return 0
}

PLANS_ABSORBING=()
for plan in "${ADDED_PLAN_FILES[@]:-}"; do
  [ -n "$plan" ] || continue
  if plan_absorbs_items "$plan"; then
    PLANS_ABSORBING+=("$plan")
  fi
done

# ---------- decision (shared by enforce AND --check — R3.4) --------------
#
# _bpa_print_block <check_mode> — the ONE structured-message emitter. Both
# the enforce path and --check call this with the same PLANS_ABSORBING
# array computed above; the only difference is the header wording and
# whether the caller treats exit 1 as an actual block or an advisory
# verdict. Fields: WHAT / WHY / FIX / ESCAPE (R3.4 Gate Philosophy Law —
# doctor-lintable structured block message).
_bpa_print_block() {
  local check_mode="$1"
  local header="BACKLOG-PLAN ATOMICITY GATE — BLOCKED"
  if [ "$check_mode" -eq 1 ]; then
    header="BACKLOG-PLAN ATOMICITY GATE — [--check] WOULD BLOCK"
  fi
  {
    echo ""
    echo "================================================================"
    echo "$header"
    echo "================================================================"
    echo ""
    echo "WHAT: The following new plan(s) declare 'Backlog items absorbed:' with"
    echo "      a non-empty list, but docs/backlog.md is NOT staged in this"
    echo "      commit:"
    echo ""
    for p in "${PLANS_ABSORBING[@]}"; do
      echo "        - $p"
    done
    echo ""
    echo "WHY:  Rule 1 of the document-freshness system: plan creation absorbs"
    echo "      backlog items. Items claimed by a plan must be deleted from"
    echo "      docs/backlog.md in the SAME commit — otherwise the backlog and"
    echo "      the plan drift out of sync and items get tracked in two places."
    echo ""
    echo "FIX:  1. Open docs/backlog.md"
    echo "      2. Remove the items listed in the plan's header"
    echo "      3. Update the 'Last updated' date"
    echo "      4. git add docs/backlog.md"
    echo "      5. Re-run the commit"
    echo ""
    echo "      If this plan genuinely absorbs no backlog items, change the"
    echo "      header line to: 'Backlog items absorbed: none'"
    echo ""
    echo "ESCAPE: git commit --no-verify"
    echo "      Cost: skips the WHOLE pre-commit chain, not just this gate —"
    echo "      every other freshness/TDD/hygiene gate in the chain is also"
    echo "      bypassed, and the backlog/plan drift this gate exists to"
    echo "      prevent ships unrecorded until someone notices by hand. The"
    echo "      FIX above is 5 commands and closes the loop properly instead."
    echo ""
    echo "This gate: ~/.claude/hooks/backlog-plan-atomicity.sh (source: adapters/claude-code/hooks/backlog-plan-atomicity.sh)"
    if [ "$check_mode" -eq 1 ]; then
      echo "[--check mode: advisory only, no side effects — re-run without"
      echo " --check to see this enforced for real at commit time]"
    fi
    echo "================================================================"
  } >&2
}

if [ "${#PLANS_ABSORBING[@]}" -gt 0 ] && [ "$HAS_BACKLOG_STAGED" -eq 0 ]; then
  _bpa_print_block "$CHECK_MODE"
  exit 1
fi

if [ "$CHECK_MODE" -eq 1 ]; then
  echo "[backlog-plan-atomicity --check] would-pass" >&2
fi
exit 0
