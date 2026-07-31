#!/bin/bash
# measure-review-gate-fp.sh — retroactive false-positive measurement for
# hooks/review-record-commit-gate.sh.
#
# WHY THIS EXISTS: constitution §10 requires a measured false-positive
# expectation before a BLOCKING gate ships. The usual way to get one is a
# warn-mode calibration period, which costs a week of wall-clock and produces
# nothing until it ends. This script gets the same evidence in minutes by
# replaying the gate's PREDICATE over real history: for each of the last N
# commits, would the gate have blocked it?
#
# It answers the question the operator actually cares about — "how often will
# this thing get in my way, and for what kind of work" — before the gate is ever
# armed, and it re-runs on demand afterwards to detect drift.
#
# HONEST LIMIT, stated up front: this measures the gate's TRIGGER, not the
# counterfactual world. In a world where the gate existed, those commits would
# have carried review records, so the true steady-state block rate is LOWER than
# what this reports. This number is therefore an UPPER BOUND on obstruction, and
# it is the right bound to judge a blocking gate on.
#
# Usage: measure-review-gate-fp.sh [--commits N] [--verbose]

set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../../.." && pwd)"
N=300
VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --commits) N="${2:-300}"; shift 2 ;;
    --verbose) VERBOSE=1; shift ;;
    *) shift ;;
  esac
done

# shellcheck source=/dev/null
source "$SELF_DIR/../hooks/lib/review-record-gate-lib.sh" 2>/dev/null || {
  echo "cannot source review-record-gate-lib.sh" >&2; exit 2; }

cd "$REPO_ROOT" || exit 2

triggered=0      # commits touching >=1 in-surface file
would_block=0    # commits with >=1 uncovered in-surface file
declare -a BLOCKED_SHAS=()

# class counters (bash 3.2: no associative arrays)
c_feat=0; c_fix=0; c_docs=0; c_chore=0; c_refactor=0; c_verify=0; c_doctrine=0; c_other=0
# exemption-class counters — the true-FP candidates
e_revert=0; e_merge=0; e_bot=0

while IFS= read -r sha; do
  [[ -n "$sha" ]] || continue
  # files added/copied/modified/renamed in this commit (deletions excluded, as
  # the gate excludes them)
  files="$(git show --name-only --format= --diff-filter=ACMR "$sha" 2>/dev/null)"
  [[ -n "$files" ]] || continue

  hit=0; uncovered_here=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    rrg_in_surface "$f" || continue
    hit=1
    # the blob AS OF that commit
    blob="$(git rev-parse "$sha:$f" 2>/dev/null)" || blob=""
    [[ -n "$blob" ]] || continue
    if ! rrg_is_covered "$REPO_ROOT" "$sha" "$f" "$blob"; then
      uncovered_here=1
    fi
  done <<< "$files"

  [[ "$hit" -eq 1 ]] && triggered=$((triggered+1))
  [[ "$uncovered_here" -eq 1 ]] || continue

  would_block=$((would_block+1))
  BLOCKED_SHAS+=("$sha")
  subj="$(git log -1 --format=%s "$sha" 2>/dev/null)"
  parents="$(git log -1 --format=%P "$sha" 2>/dev/null | wc -w | tr -d ' ')"

  # classify by message prefix
  case "$subj" in
    feat*) c_feat=$((c_feat+1)) ;;
    fix*) c_fix=$((c_fix+1)) ;;
    docs*) c_docs=$((c_docs+1)) ;;
    chore*) c_chore=$((c_chore+1)) ;;
    refactor*) c_refactor=$((c_refactor+1)) ;;
    verify*) c_verify=$((c_verify+1)) ;;
    doctrine*) c_doctrine=$((c_doctrine+1)) ;;
    *) c_other=$((c_other+1)) ;;
  esac

  # TRUE-FP candidates: commits a reasonable operator would say should never
  # have been blocked
  case "$subj" in
    Revert*|revert*) e_revert=$((e_revert+1)); echo "  TRUE-FP(revert)   $sha $subj" ;;
  esac
  [[ "$parents" -gt 1 ]] && { e_merge=$((e_merge+1)); echo "  TRUE-FP(merge)    $sha $subj"; }
  author="$(git log -1 --format=%an "$sha" 2>/dev/null)"
  case "$author" in
    *[Bb]ot*|*[Aa]ction*) e_bot=$((e_bot+1)); echo "  TRUE-FP(bot)      $sha $subj" ;;
  esac
  [[ "$VERBOSE" -eq 1 ]] && echo "  would-block: $sha $subj"
done < <(git log --format=%H -n "$N" 2>/dev/null)

true_fp=$((e_revert + e_merge + e_bot))

echo "================================================================"
echo "REVIEW-RECORD COMMIT GATE — retroactive false-positive measurement"
echo "================================================================"
echo "commits examined                : $N"
echo "commits touching in-surface files (gate TRIGGER population) : $triggered"
echo "commits the gate WOULD have blocked                         : $would_block"
echo
echo "would-block by commit class:"
printf '  feat=%s fix=%s docs=%s chore=%s refactor=%s verify=%s doctrine=%s other=%s\n' \
  "$c_feat" "$c_fix" "$c_docs" "$c_chore" "$c_refactor" "$c_verify" "$c_doctrine" "$c_other"
echo
echo "TRUE false positives (classes that should never be blocked):"
printf '  reverts=%s merges=%s bot/automated=%s   TOTAL=%s\n' \
  "$e_revert" "$e_merge" "$e_bot" "$true_fp"
echo
echo "POPULATION VALIDITY — read this before quoting the rate above:"
echo "  Merge commits produce an EMPTY --diff-filter=ACMR list, so they exit this"
echo "  loop before classification: e_merge CANNOT be non-zero here, and a 0 in"
echo "  that column is a property of git, not a measurement."
echo "  Deletion-only commits likewise produce an empty list. The old"
echo "  'deletion-only' counter was dead code and has been removed rather than"
echo "  reported as a measured zero."
echo "  If reverts=0 and bots=0 below, check whether ANY revert or bot commit"
echo "  exists in the window at all — if none does, the true-FP rate is 0 over an"
echo "  empty numerator and is NOT evidence of anything."
if [[ "$would_block" -gt 0 ]]; then
  pct=$(( true_fp * 100 / would_block ))
  echo "  measured false-positive rate = $true_fp / $would_block = ${pct}%"
else
  echo "  measured false-positive rate = n/a (nothing would have blocked)"
fi
echo
echo "BOOTSTRAP SPLIT (the honest number):"
pre=0; post=0; post_block=0
while IFS= read -r sha; do
  [[ -n "$sha" ]] || continue
  if git cat-file -e "$sha:docs/reviews/records/index.json" 2>/dev/null; then
    post=$((post+1))
  else
    pre=$((pre+1))
  fi
done < <(git log --format=%H -n "$N" 2>/dev/null)
echo "  commits PREDATING docs/reviews/records/ (rrg fail-opens -> counted covered): $pre"
echo "  commits AFTER the records dir existed                                     : $post"
echo "  Any gap between 'triggered' and 'would block' above is largely this"
echo "  fail-open, NOT commits that legitimately carried a review record."
echo
echo "READ THIS AS AN UPPER BOUND. These commits predate the gate, so none of"
echo "them carry a review record. In steady state a compliant commit carries its"
echo "record and does not block, so real-world obstruction is strictly lower."
echo "================================================================"
