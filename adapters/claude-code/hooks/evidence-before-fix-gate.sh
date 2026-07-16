#!/bin/bash
# evidence-before-fix-gate.sh — Directive 1, "the 5th lesson"
# (harness-governance-batch-2026-07-15, batch task 3).
#
# Classification: Mechanism, WARN-MODE (hook-enforced PreToolUse; never blocks)
#
# WARN-MODE, NOT BLOCKING (harness-review REJECT remediation, 2026-07-16):
# harness-reviewer PROVEN two miscalibrations in the original blocking design:
#   (a) OVER-FIRE: `git log -400 --format=%s | grep -cE '^fix(\(|:)'` = 61/400
#       (~15%; reviewer's own -300 sample measured ~13%) of this repo's own
#       commits match the trigger. A manual skim of that sample shows the
#       DOMINANT class is harness maintenance / review-remediation fixes
#       ("fix(review): address harness-review findings", "fix(wave-o): ...")
#       -- NOT incident-forensics-shaped bugs with an observable row/log to
#       cite. The manifest's original fp_expectation ("Low") was wrong.
#   (b) SILENT FAIL-OPEN: the message-extraction parser (below) PROVEN to
#       miss glued `-m"..."`, `--message=`/`-m=`, multiple `-m` segments, and
#       `--amend --no-edit` -- a `fix(...)` commit in any of those shapes
#       passed with ZERO evidence check, silently.
# Promoting-to-block on a parser with proven fail-open holes plus a measured
# ~13-15% over-fire rate (dominated by a class the gate's own rationale
# doesn't fit) would have bricked real maintenance work. WARN-MODE is the
# calibration period: the gate ALWAYS exits 0 -- it teaches, via the full
# banner (stderr + hookSpecificOutput.additionalContext so the acting model
# sees it too), but never blocks a commit.
#
# PROMOTION CONDITION (tracked at docs/backlog.md
# EVIDENCE-BEFORE-FIX-PROMOTION-01): promote blocking:true only after a
# measured calibration period shows the over-fire class (non-incident
# maintenance/review-remediation fixes) is EITHER separable by a trigger
# refinement (e.g., excluding a `fix(review)`/`fix(wave-*)`-style scope, or
# requiring an incident/finding-ID reference to even apply) OR acceptably
# rare once the parser-reach gaps in (b) are closed and re-measured. Method:
# the reviewer's own sweep -- `git log -N --format=%s`, bucket matches into
# {incident-shaped, review/audit-remediation, refactor/typo, other}, report
# the share and the bucket breakdown.
#
# Classification: Mechanism (hook-enforced PreToolUse; WARN-MODE per above)
#
# Rule: docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md
# Doctrine: adapters/claude-code/doctrine/evidence-before-fix.md (compact --
#           states the doctrine/mechanism scope mismatch: the RULE is scoped
#           to observed defects, but the TRIGGER (any fix(/fix: subject) is
#           broader than that by construction -- warn-mode is the
#           calibration for exactly this gap, not a claim the mismatch is
#           resolved)
#           adapters/claude-code/doctrine/diagnosis.md (broadened by this task
#           beyond prod-crashes to any data/behavior/state defect)
#
# WHY THIS IS WIRED AS AN INDEPENDENT PreToolUse HOOK, NOT NESTED IN THE
# pre-commit-gate.sh FRESHNESS_GATES CHAIN
# ============================================================================
# docs-freshness-gate.sh / decisions-index-gate.sh / review-finding-fix-gate.sh
# are invoked from INSIDE pre-commit-gate.sh, itself invoked from a wrapper
# PreToolUse command that does:
#   CMD=$(jq -r '.tool_input.command // ""'); if <CMD matches git commit>; then
#     bash ~/.claude/hooks/pre-commit-gate.sh || exit 1
#   fi
# `jq` there consumes the hook's stdin (the PreToolUse JSON payload) in full to
# populate $CMD; $CMD is a local (non-exported) shell variable, so
# pre-commit-gate.sh and everything it calls inherit NEITHER a populated stdin
# NOR $CMD. review-finding-fix-gate.sh compensates by reading
# `.git/COMMIT_EDITMSG` instead — but PROVEN (reproduced empirically while
# building this gate; see below) that file holds the PREVIOUS commit's
# message at PreToolUse time, not the one about to be made:
#
#   $ git commit -m "first"                  # writes COMMIT_EDITMSG="first"
#   $ git add x && git commit -m "second"    # pre-commit hook sees
#                                             #   COMMIT_EDITMSG == "first"
#                                             #   (git writes the NEW
#                                             #   COMMIT_EDITMSG only once the
#                                             #   commit's message-prep step
#                						#   runs, which is AFTER pre-commit)
#
# A gate that needs the CURRENT message (this one does — it inspects the
# body for a `## Root cause (evidenced)` section and any `frc-...` record
# reference) cannot rely on COMMIT_EDITMSG at PreToolUse time. This is flagged
# as a real, reproduced defect in review-finding-fix-gate.sh's existing
# design (out of scope to fix here; see the build's final report / nl-issue).
# Instead this gate is wired as its OWN top-level PreToolUse "Bash" hooks[]
# entry (same wiring shape as observed-errors-gate.sh), reading the command
# string directly from CLAUDE_TOOL_INPUT / stdin JSON BEFORE the real git
# process ever runs — the only point at which the upcoming message is known.
#
# BEHAVIOR
# ========
#   1. Not a `git commit ...` command                        -> ALLOW (silent)
#   2. Merge/rebase/cherry-pick in progress, or message's
#      first line starts with "Merge branch"                 -> ALLOW (skip)
#   3. Subject line does not start with `fix(` or `fix:`      -> ALLOW (silent)
#      (`fix-trivial:` never matches either prefix -- the decided lighter
#      path for changes touching NO runtime/product code; see doctrine file)
#   4. Message body has a `## Root cause (evidenced)` section with >=1
#      `PROVEN`-tagged line carrying a citation-shaped token (file:line,
#      backtick-quoted command/output, or a command:/output:/log: label)
#                                                              -> ALLOW (silent)
#   5. Message cites a `frc-YYYYMMDD-xxxxxxxx` review-record id whose record
#      (docs/reviews/records/*.json) has kind fix-root-cause, verdict PASS,
#      covered_files intersecting the staged file set, and
#      payload.root_cause.tag PROVEN (or INFERRED with blast_radius_bounded
#      true)                                                  -> ALLOW (silent)
#   6. A fresh (<1h) .claude/state/evidence-before-fix-waiver-*.txt names
#      both purpose clauses (lib/waiver-purpose-clause.sh) AND a Files: line
#      matching >=1 staged file                               -> ALLOW (loud)
#   7. None of the above                                      -> WARN, exit 0
#      (teaching banner to stderr + hookSpecificOutput.additionalContext;
#      the commit is NEVER blocked -- see WARN-MODE note above)
#
# HONESTY NOTE (structure-not-truth, named per the task's instruction): this
# gate can verify the SECTION EXISTS, is TAGGED, and CITES a token shaped
# like evidence -- it cannot verify the citation is true, that the command
# was actually run, or that the quoted log excerpt is real. Path 5's record
# reference inherits the SAME residual write-review-record.sh already names
# (Amendment C, docs/design-notes/review-record-primitive.md): the record's
# audit trail (append-only, content-addressed, requiring an actual reviewer
# dispatch to produce a record id) is the compensating control, not a
# guarantee. A determined agent can fabricate a citation-shaped string. This
# gate raises the cost of shipping an inferred-only fix; it does not make
# fabrication impossible. A PROVEN prose line WITHOUT one of the citation
# shapes (file:line / backtick-quoted command-or-output / a command:,
# output:, or log: label) does NOT satisfy path 4 -- plain prose asserting
# "I confirmed this" is not itself a citation.
#
# PARSER RESIDUAL (harness-review PROVEN, disclosed not solved): message
# extraction below handles heredoc (dominant convention), glued/spaced -m
# and --message (with or without `=`), multiple -m segments (concatenated,
# git's own paragraph-join behavior), -F <file>, and a best-effort
# `--amend`-with-no-explicit-message proxy (reads the CURRENT HEAD message
# via `git log -1 --format=%B` -- correct, not stale, because amend reuses
# HEAD's message and HEAD has not changed yet at PreToolUse time; unlike the
# `.git/COMMIT_EDITMSG` case above, this read is NOT a proven-stale
# anti-pattern). Genuinely unparseable shapes (a message built via complex
# nested shell interpolation/variable substitution the static command string
# does not literally contain, or an interactive `--amend` where the editor
# will change HEAD's message) still silently produce no evidence check --
# in WARN-MODE this is a lower-stakes residual than it was under blocking
# (nothing is blocked either way), but it is still a real gap: a triggering
# commit in an unparseable shape gets NO teaching banner either.
#
# INVOCATION
#   1. PreToolUse (Bash matcher), independently wired in
#      settings.json.template -- reads CLAUDE_TOOL_INPUT env var or stdin
#      JSON ({"tool_input":{"command": "..."}}), no args.
#   2. Self-test: evidence-before-fix-gate.sh --self-test
#
# EXIT CODES
#   0 -- ALWAYS (warn-mode never blocks; see WARN-MODE note above). A
#        teaching banner is printed to stderr + hookSpecificOutput when a
#        triggering commit lacks evidence; the commit still proceeds.

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/waiver-purpose-clause.sh
source "$SELF_DIR/lib/waiver-purpose-clause.sh" 2>/dev/null || true
# shellcheck source=lib/signal-ledger.sh
source "$SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true

# ============================================================================
# Commit-message extraction (mirrors observed-errors-gate.sh's proven
# extraction logic -- the same underlying problem: get the message text out
# of a Bash tool_input.command string before the real `git commit` runs).
#
# Parser reach (harness-review PROVEN gaps, fixed here): glued `-m"..."` /
# `-m'...'` (no space before the quote), `--message`/`-m` with `=`
# (`--message=foo`, `-m=foo`), MULTIPLE -m/--message occurrences (git
# concatenates each as its own paragraph -- so do we), and a best-effort
# `--amend`-with-no-explicit-message proxy. See PARSER RESIDUAL header note
# for what remains genuinely unhandled (disclosed, not silently claimed
# solved).
# ============================================================================

# _efg_all_matches_dq/_sq/_bare <command> -- echo, one per line, in order of
# appearance, the VALUE of every -m/--message occurrence using ONE quote
# style (double, single, or bare-unquoted respectively). Kept as three
# single-style scanners (not one mixed-alternation regex) specifically to
# avoid the nested-quote escaping hazard of embedding both `'` and `"`
# literals in one bash ERE string; a command mixing quote styles across
# multiple -m flags in the SAME invocation is a named, disclosed residual
# (rare in practice -- an agent picks one quote style per command).
_efg_all_matches_dq() {
  local cmdstr="$1"
  local remaining="$cmdstr"
  local re='(^|[[:space:]])(-m|--message)[[:space:]]*=?[[:space:]]*"([^"]*)"'
  while [[ "$remaining" =~ $re ]]; do
    printf '%s\n' "${BASH_REMATCH[3]}"
    local whole="${BASH_REMATCH[0]}"
    local next="${remaining#*"$whole"}"
    [[ "$next" == "$remaining" ]] && break   # safety: no progress, stop
    remaining="$next"
  done
}

_efg_all_matches_sq() {
  local cmdstr="$1"
  local remaining="$cmdstr"
  local re="(^|[[:space:]])(-m|--message)[[:space:]]*=?[[:space:]]*'([^']*)'"
  while [[ "$remaining" =~ $re ]]; do
    printf '%s\n' "${BASH_REMATCH[3]}"
    local whole="${BASH_REMATCH[0]}"
    local next="${remaining#*"$whole"}"
    [[ "$next" == "$remaining" ]] && break
    remaining="$next"
  done
}

_efg_all_matches_bare() {
  local cmdstr="$1"
  local remaining="$cmdstr"
  local re='(^|[[:space:]])(-m|--message)[[:space:]]*=?[[:space:]]*([^[:space:]]+)'
  while [[ "$remaining" =~ $re ]]; do
    printf '%s\n' "${BASH_REMATCH[3]}"
    local whole="${BASH_REMATCH[0]}"
    local next="${remaining#*"$whole"}"
    [[ "$next" == "$remaining" ]] && break
    remaining="$next"
  done
}

# _efg_join_paragraphs <newline-separated-values> -- join with a blank line
# between each (git's own multi -m concatenation behavior).
_efg_join_paragraphs() {
  local segs="$1" joined="" first=1 seg
  while IFS= read -r seg; do
    if [[ "$first" -eq 1 ]]; then joined="$seg"; first=0
    else joined="${joined}"$'\n\n'"${seg}"; fi
  done <<< "$segs"
  printf '%s' "$joined"
}

_efg_extract_commit_message() {
  local COMMAND="$1"

  # Heredoc-style (the harness's own documented convention: git commit -m
  # "$(cat <<'EOF' ... EOF)"). Dominant real-world shape for any multi-line
  # message (which a "## Root cause (evidenced)" section requires) --
  # checked FIRST and, when present, wins outright (a heredoc body can
  # itself contain a line that looks like `-m "..."` as prose).
  if echo "$COMMAND" | grep -qE "<<['\"]?EOF['\"]?[[:space:]]*\$"; then
    local heredoc_msg
    heredoc_msg=$(printf '%s\n' "$COMMAND" | awk '/<<[[:space:]]*.?EOF.?[[:space:]]*$/{flag=1; next} /^EOF[[:space:]]*$/{flag=0} flag' 2>/dev/null || echo "")
    if [[ -n "$heredoc_msg" ]]; then
      printf '%s' "$heredoc_msg"
      return 0
    fi
  fi

  # -m / --message: try one quote style at a time (double, then single, then
  # bare-unquoted); concatenate ALL occurrences found in that style.
  local segs
  segs=$(_efg_all_matches_dq "$COMMAND")
  [[ -z "$segs" ]] && segs=$(_efg_all_matches_sq "$COMMAND")
  [[ -z "$segs" ]] && segs=$(_efg_all_matches_bare "$COMMAND")
  if [[ -n "$segs" ]]; then
    _efg_join_paragraphs "$segs"
    return 0
  fi

  # -F <file>
  if echo "$COMMAND" | grep -qE '\-F[[:space:]]'; then
    local msg_file
    msg_file=$(echo "$COMMAND" | sed -nE 's/.*-F[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
    if [[ -n "$msg_file" && -f "$msg_file" ]]; then
      printf '%s' "$(cat "$msg_file" 2>/dev/null || echo "")"
      return 0
    fi
  fi

  printf ''
}

# _efg_amend_proxy_message <command> <repo_root> -- best-effort proxy for
# `git commit --amend` with NO explicit -m/-F/heredoc: reads HEAD's CURRENT
# message (git log -1 --format=%B). Correct, not stale: amend reuses HEAD's
# message verbatim and HEAD has not changed yet at PreToolUse time -- unlike
# reading .git/COMMIT_EDITMSG (proven stale, see header), this reads
# already-committed, unambiguous content. Residual: an INTERACTIVE amend
# (editor opens) may change the message before it lands; this proxy cannot
# see that edit.
_efg_amend_proxy_message() {
  local cmdstr="$1" repo_root="$2"
  echo "$cmdstr" | grep -qE '(^|[[:space:]])--amend([[:space:]]|$)' || { printf ''; return 0; }
  git -C "$repo_root" log -1 --format=%B 2>/dev/null
}

# ============================================================================
# Merge/rebase/cherry-pick detection (scope-enforcement-gate.sh's precedent,
# extended with CHERRY_PICK_HEAD per this task's explicit instruction).
# ============================================================================
_efg_resolve_git_dir_abs() {
  local gd="$1" root="$2"
  case "$gd" in
    "") printf '' ;;
    /*) printf '%s' "$gd" ;;
    [A-Za-z]:/*|[A-Za-z]:\\*) printf '%s' "$gd" ;;
    *) printf '%s/%s' "$root" "$gd" ;;
  esac
}

_efg_in_replay_context() {
  local repo_root="$1" first_line="$2"
  local git_dir git_dir_abs
  git_dir=$(git -C "$repo_root" rev-parse --git-dir 2>/dev/null)
  git_dir_abs=$(_efg_resolve_git_dir_abs "$git_dir" "$repo_root")
  if [[ -n "$git_dir_abs" ]]; then
    [[ -f "$git_dir_abs/MERGE_HEAD" ]] && return 0
    [[ -f "$git_dir_abs/CHERRY_PICK_HEAD" ]] && return 0
    [[ -d "$git_dir_abs/rebase-apply" ]] && return 0
    [[ -d "$git_dir_abs/rebase-merge" ]] && return 0
  fi
  case "$first_line" in
    "Merge branch"*) return 0 ;;
  esac
  return 1
}

# ============================================================================
# "## Root cause (evidenced)" section extraction + PROVEN/citation check.
# ============================================================================
_efg_section_text() {
  local msg="$1"
  printf '%s\n' "$msg" | awk '
    /^## Root cause \(evidenced\)[[:space:]]*$/ { flag=1; next }
    /^## / { if (flag) exit }
    flag { print }
  '
}

_efg_line_has_citation() {
  local line="$1"
  # file:line reference, e.g. adapters/claude-code/hooks/foo.sh:123
  if printf '%s' "$line" | grep -qE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+'; then
    return 0
  fi
  # backtick-quoted command or output excerpt
  if printf '%s' "$line" | grep -qE '`[^`]+`'; then
    return 0
  fi
  # explicit command:/output:/log: label with content following
  if printf '%s' "$line" | grep -qiE '(command|output|log)[[:space:]]*:[[:space:]]*[^[:space:]]'; then
    return 0
  fi
  return 1
}

# Sets globals: EFG_SECTION_PRESENT, EFG_SECTION_SATISFIED,
# EFG_SECTION_HAS_PROVEN_NO_CITATION (diagnostic detail for the block message)
_efg_check_inline_section() {
  local msg="$1"
  EFG_SECTION_PRESENT=0
  EFG_SECTION_SATISFIED=0
  EFG_SECTION_HAS_PROVEN_NO_CITATION=0

  local section
  section=$(_efg_section_text "$msg")
  [[ -z "$section" ]] && return 0
  EFG_SECTION_PRESENT=1

  local any_proven_with_citation=0 any_proven=0
  while IFS= read -r line; do
    if printf '%s' "$line" | grep -qE '\bPROVEN\b'; then
      any_proven=1
      if _efg_line_has_citation "$line"; then
        any_proven_with_citation=1
      fi
    fi
  done <<< "$section"

  if [[ "$any_proven_with_citation" -eq 1 ]]; then
    EFG_SECTION_SATISFIED=1
  elif [[ "$any_proven" -eq 1 ]]; then
    EFG_SECTION_HAS_PROVEN_NO_CITATION=1
  fi
  return 0
}

# ============================================================================
# Record-reference path (kind: fix-root-cause).
# ============================================================================
# Sets globals: EFG_RECORD_TOKEN, EFG_RECORD_RESULT (ok|not-found|not-pass|
#   no-coverage|inferred-unbounded), EFG_RECORD_DETAIL
_efg_check_record_reference() {
  local msg="$1" repo_root="$2"
  EFG_RECORD_TOKEN=""
  EFG_RECORD_RESULT="none"
  EFG_RECORD_DETAIL=""

  local token
  token=$(printf '%s' "$msg" | grep -oE 'frc-[0-9]{8}-[0-9a-f]{8}' | head -1)
  [[ -z "$token" ]] && return 0
  EFG_RECORD_TOKEN="$token"

  command -v jq >/dev/null 2>&1 || { EFG_RECORD_RESULT="not-found"; EFG_RECORD_DETAIL="jq unavailable -- cannot verify record"; return 0; }

  local records_dir="$repo_root/docs/reviews/records"
  [[ -d "$records_dir" ]] || { EFG_RECORD_RESULT="not-found"; EFG_RECORD_DETAIL="no docs/reviews/records/ directory"; return 0; }

  local f match=""
  shopt -s nullglob
  for f in "$records_dir"/*.json; do
    local base; base=$(basename "$f")
    [[ "$base" == "index.json" || "$base" == "grandfather-manifest.json" ]] && continue
    if jq -e --arg id "$token" '.record_id == $id' "$f" >/dev/null 2>&1; then
      match="$f"
      break
    fi
  done
  shopt -u nullglob

  if [[ -z "$match" ]]; then
    EFG_RECORD_RESULT="not-found"
    EFG_RECORD_DETAIL="no record file has record_id == $token"
    return 0
  fi

  local kind verdict tag bounded
  kind=$(jq -r '.kind // ""' "$match" 2>/dev/null)
  verdict=$(jq -r '.verdict // ""' "$match" 2>/dev/null)
  tag=$(jq -r '.payload.root_cause.tag // ""' "$match" 2>/dev/null)
  bounded=$(jq -r '.payload.blast_radius_bounded // false' "$match" 2>/dev/null)

  if [[ "$kind" != "fix-root-cause" ]]; then
    EFG_RECORD_RESULT="not-found"
    EFG_RECORD_DETAIL="record $token has kind '$kind', expected fix-root-cause"
    return 0
  fi
  if [[ "$verdict" != "PASS" ]]; then
    EFG_RECORD_RESULT="not-pass"
    EFG_RECORD_DETAIL="record $token has verdict '$verdict', not PASS"
    return 0
  fi

  # Coverage: covered_files must intersect the staged file set.
  local staged="$3"
  local covered=0 p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if jq -e --arg p "$p" '.covered_files[]? | select(.path == $p)' "$match" >/dev/null 2>&1; then
      covered=1
      break
    fi
  done <<< "$staged"

  if [[ "$covered" -eq 0 ]]; then
    EFG_RECORD_RESULT="no-coverage"
    EFG_RECORD_DETAIL="record $token's covered_files does not include any staged file"
    return 0
  fi

  if [[ "$tag" == "PROVEN" ]]; then
    EFG_RECORD_RESULT="ok"
    return 0
  fi
  if [[ "$tag" == "INFERRED" && "$bounded" == "true" ]]; then
    EFG_RECORD_RESULT="ok"
    return 0
  fi

  EFG_RECORD_RESULT="inferred-unbounded"
  EFG_RECORD_DETAIL="record $token has payload.root_cause.tag='$tag' (blast_radius_bounded=$bounded) -- an INFERRED cause requires blast_radius_bounded=true"
  return 0
}

# ============================================================================
# Structured waiver (harness-hygiene-scan.sh precedent -- NEVER an env var).
# ============================================================================
_efg_waiver_covers_staged() {
  local repo_root="$1" staged="$2"
  local state_dir="$repo_root/.claude/state"
  [[ -d "$state_dir" ]] || return 1

  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if declare -F waiver_has_purpose_clauses >/dev/null 2>&1; then
      waiver_has_purpose_clauses "$f" || continue
    fi
    local named
    named=$(grep -iE '^[[:space:]]*files[[:space:]]*:' "$f" 2>/dev/null \
      | sed -E 's/^[[:space:]]*[Ff][Ii][Ll][Ee][Ss][[:space:]]*:[[:space:]]*//' \
      | tr ', ' '\n\n')
    local p n
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      while IFS= read -r n; do
        [[ -z "$n" ]] && continue
        [[ "$p" == "$n" ]] && return 0
      done <<< "$staged"
    done <<< "$named"
  done < <(find "$state_dir" -maxdepth 1 -type f -name 'evidence-before-fix-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null)
  return 1
}

# ============================================================================
# Teaching banner (WARN-MODE: always exits 0; never blocks the commit).
# Mirrors observed-errors-gate.sh's _demote_warn convention: stderr copy +
# hookSpecificOutput.additionalContext (so the ACTING MODEL sees the note,
# not only a human reading the terminal) + a signal-ledger "warn" event.
# ============================================================================
_efg_warn_banner_body() {
  local reason="$1" detail="$2"
  cat <<EOF

================================================================
EVIDENCE-BEFORE-FIX GATE — WARN (not blocked; warn-mode pending calibration)
================================================================

This fix ships without evidenced root cause -- here are the four ways to
carry evidence. Reason: $reason
$( [[ -n "$detail" ]] && echo "  ($detail)" )

This gate does NOT block (warn-mode, tracked at docs/backlog.md
EVIDENCE-BEFORE-FIX-PROMOTION-01) -- the commit will proceed regardless.
This banner exists to teach the habit while the gate's trigger is being
calibrated against real commit traffic (measured ~13-15% of this repo's own
fix(/fix: commits are harness-maintenance/review-remediation, not
incident-shaped -- see the header comment).

Rule: docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md
Doctrine: adapters/claude-code/doctrine/evidence-before-fix.md

"I found a code path that could cause this" is inference. "The logs/data
show this IS what happened" is evidence. A fix may only ship on the latter.

Four ways to carry evidence:

  1. Add a section to the commit message body:

       ## Root cause (evidenced)
       PROVEN: <what you observed> (cite: file:line, a backtick-quoted
         command/output, or a command:/output:/log: line)

     A PROVEN line WITHOUT one of those citation shapes does NOT satisfy
     this -- plain prose asserting "I confirmed this" is not itself a
     citation. A section with ONLY INFERRED-tagged lines does not satisfy
     it either -- an inferred cause should be OBSERVED before shipping,
     where an observation is reachable.

  2. Reference a fix-root-cause review record: get one written via
     scripts/write-review-record.sh capture --kind fix-root-cause ..., then
     cite its record_id (frc-YYYYMMDD-xxxxxxxx) in the commit message. The
     record should be verdict PASS, cover a staged file, and have
     payload.root_cause.tag PROVEN (or INFERRED with blast_radius_bounded
     true).

  3. Genuinely trivial fix -- touches NO runtime/product code (docs,
     comments, formatting only, no behavior change)? Use 'fix-trivial:'
     instead of 'fix:'/'fix(...)' -- it never triggers this gate. Reserved
     for changes a reviewer can spot-check correct by eye from the diff
     alone; if the diff touches any runtime/product file, use fix(...) and
     one of options 1/2 instead.

  4. Evidence genuinely unreachable? Write a structured waiver (silences
     this banner, still doesn't block anything since warn-mode already
     doesn't):
       mkdir -p .claude/state
       {
         echo "Purpose: this gate exists to prevent <X>"
         echo "Because: <Y -- name the missing datum + how you tried to"
         echo "  reach it; bound the fix to fail-safe (fail-open /"
         echo "  shadow-first) and say so here>"
         echo "Files: <staged file path(s), space-separated>"
       } > .claude/state/evidence-before-fix-waiver-\$(date +%s).txt
     Re-run the commit (waiver is honored for 1 hour).

HONESTY NOTE: this gate checks STRUCTURE (a tagged section with a
citation-shaped token, or a record's existence/coverage), not TRUTH -- it
cannot verify a citation is real. The record path's audit trail
(append-only, content-addressed) is the compensating control.
================================================================
EOF
}

_efg_warn() {
  local reason="$1" detail="$2" first_line="$3"
  local body
  body="$(_efg_warn_banner_body "$reason" "$detail")"
  echo "$body" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "[evidence-before-fix-gate] WARN (warn-mode pending calibration, does not block): ${reason}
${body}" '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$ctx}}'
  fi
  command -v ledger_emit >/dev/null 2>&1 && ledger_emit "evidence-before-fix-gate" "warn" "$reason ($first_line)"
}

# ============================================================================
# Main
# ============================================================================
main() {
  local INPUT
  INPUT="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$INPUT" ]]; then
    if [[ ! -t 0 ]]; then
      INPUT=$(cat 2>/dev/null || echo "")
    fi
  fi

  local COMMAND
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || echo "")
  [[ -z "$COMMAND" ]] && exit 0

  echo "$COMMAND" | grep -qE '(^|[[:space:];&|])git[[:space:]]+commit([[:space:]]|$)' || exit 0
  echo "$COMMAND" | grep -qE 'git[[:space:]]+commit-tree' && exit 0

  local REPO_ROOT
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  [[ -z "$REPO_ROOT" ]] && exit 0

  local COMMIT_MSG
  COMMIT_MSG=$(_efg_extract_commit_message "$COMMAND")
  if [[ -z "$COMMIT_MSG" ]]; then
    # --amend with no explicit -m/-F/heredoc: best-effort proxy via HEAD's
    # current message (see _efg_amend_proxy_message -- not stale, unlike
    # .git/COMMIT_EDITMSG).
    COMMIT_MSG=$(_efg_amend_proxy_message "$COMMAND" "$REPO_ROOT")
    if [[ -n "$COMMIT_MSG" ]]; then
      echo "[evidence-before-fix-gate] --amend with no explicit message -- using HEAD's current message as a best-effort proxy (an interactive edit could still change it)." >&2
    fi
  fi
  [[ -z "$COMMIT_MSG" ]] && exit 0   # genuinely unparseable -- fail open (disclosed residual, see header)

  local FIRST_LINE
  FIRST_LINE=$(printf '%s\n' "$COMMIT_MSG" | head -1)

  # Skip mechanically-replayed commits.
  if _efg_in_replay_context "$REPO_ROOT" "$FIRST_LINE"; then
    echo "[evidence-before-fix-gate] merge/rebase/cherry-pick context detected -- skipping." >&2
    exit 0
  fi

  # Trigger: subject starts with fix( or fix: exactly. fix-trivial: never
  # matches either (structural FP-path, see doctrine file).
  local IS_FIX=0
  if echo "$FIRST_LINE" | grep -qE '^fix\('; then IS_FIX=1; fi
  if echo "$FIRST_LINE" | grep -qE '^fix:'; then IS_FIX=1; fi
  [[ "$IS_FIX" -eq 0 ]] && exit 0

  local STAGED
  STAGED=$(cd "$REPO_ROOT" && git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || echo "")

  # Path (a): inline evidenced section.
  _efg_check_inline_section "$COMMIT_MSG"
  if [[ "$EFG_SECTION_SATISFIED" -eq 1 ]]; then
    exit 0
  fi

  # Path (b): review-record reference.
  _efg_check_record_reference "$COMMIT_MSG" "$REPO_ROOT" "$STAGED"
  if [[ "$EFG_RECORD_RESULT" == "ok" ]]; then
    exit 0
  fi

  # Path (c): structured waiver.
  if _efg_waiver_covers_staged "$REPO_ROOT" "$STAGED"; then
    echo "[evidence-before-fix-gate] structured waiver honored." >&2
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "evidence-before-fix-gate" "waiver" "$FIRST_LINE"
    exit 0
  fi

  # WARN (never block -- warn-mode) -- determine the most specific reason.
  local reason detail
  if [[ "$EFG_SECTION_PRESENT" -eq 1 ]] && [[ "$EFG_SECTION_HAS_PROVEN_NO_CITATION" -eq 1 ]]; then
    reason="the Root cause section has a PROVEN line but no citation-shaped token"
    detail="add a file:line reference, a backtick-quoted command/output, or a command:/output:/log: line to the PROVEN line"
  elif [[ "$EFG_SECTION_PRESENT" -eq 1 ]]; then
    reason="the Root cause section contains only INFERRED-tagged lines (no PROVEN line)"
    detail="an inferred-not-observed cause should be observed where reachable, or bound the fix to fail-safe and use the waiver"
  elif [[ -n "$EFG_RECORD_TOKEN" ]]; then
    reason="the referenced record $EFG_RECORD_TOKEN did not satisfy the gate"
    detail="$EFG_RECORD_DETAIL"
  else
    reason="no ## Root cause (evidenced) section and no fix-root-cause record referenced"
    detail=""
  fi

  _efg_warn "$reason" "$detail" "$FIRST_LINE"
  exit 0
}

# ============================================================================
# --self-test
# ============================================================================
run_self_test() {
  local PASSED=0 FAILED=0 TMPDIR_ST
  TMPDIR_ST=$(mktemp -d 2>/dev/null || mktemp -d -t efgself)
  trap 'rm -rf "$TMPDIR_ST"' RETURN

  local SCRIPT_PATH
  SCRIPT_PATH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
    git config core.hooksPath ""
    git config user.email "selftest@example.test"
    git config user.name "selftest"
    mkdir -p adapters/claude-code/hooks docs/reviews/records .claude/state
    echo "v1" > adapters/claude-code/hooks/alpha.sh
    git add adapters/claude-code/hooks/alpha.sh
    git commit -q -m "init" >/dev/null 2>&1
  ) || { echo "self-test: FAIL -- repo init failed" >&2; exit 1; }

  # _run <label> <expect_warn 0|1> <commit-message> <stage-file-fn>
  # Invokes the gate via stdin JSON (jq-built, so newlines/quotes are safe).
  # Warn-mode ALWAYS exits 0 -- the real assertion is whether the WARN
  # banner fired (stderr contains the banner marker), not the exit code.
  _run() {
    local label="$1" expect_warn="$2" msg="$3" stage_fn="$4"
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      $stage_fn
      local cmd
      cmd=$(printf 'git commit -m "$(cat <<%s\n%s\n%s\n)"' "'EOF'" "$msg" "EOF")
      local input
      input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
      printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
      echo $? > rc.txt
    )
    _efg_assert_warn "$label" "$expect_warn"
  }

  # _efg_assert_warn <label> <expect_warn 0|1> -- reads rc.txt/stderr.txt from
  # the last invocation in $TMPDIR_ST. Asserts (a) rc is ALWAYS 0 (warn-mode
  # never blocks) and (b) the WARN banner marker is present/absent as
  # expected.
  _efg_assert_warn() {
    local label="$1" expect_warn="$2"
    local rc; rc=$(cat "$TMPDIR_ST/rc.txt" 2>/dev/null || echo 99)
    local has_warn=0
    grep -q "EVIDENCE-BEFORE-FIX GATE — WARN" "$TMPDIR_ST/stderr.txt" 2>/dev/null && has_warn=1
    if [[ "$rc" != "0" ]]; then
      echo "self-test ($label): FAIL (rc=$rc, expected 0 -- warn-mode must NEVER block)" >&2
      echo "  stderr: $(cat "$TMPDIR_ST/stderr.txt" 2>/dev/null | head -5)" >&2
      FAILED=$((FAILED+1))
      return
    fi
    if [[ "$has_warn" == "$expect_warn" ]]; then
      echo "self-test ($label): PASS (rc=0, warn-fired=$has_warn)" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test ($label): FAIL (warn-fired=$has_warn, expected $expect_warn)" >&2
      echo "  stderr: $(cat "$TMPDIR_ST/stderr.txt" 2>/dev/null | head -8)" >&2
      FAILED=$((FAILED+1))
    fi
  }

  stage_alpha() { echo "v2" > adapters/claude-code/hooks/alpha.sh; git add adapters/claude-code/hooks/alpha.sh; }

  # S1: fix( commit with PROVEN-tagged evidenced section + citation -> ALLOW, no warn
  _run "S1-proven-with-citation-silent-allow" 0 \
    'fix(alpha): guard against nil ptr

## Root cause (evidenced)
PROVEN: the response body at adapters/claude-code/hooks/alpha.sh:12 shows a
nil dereference (log: TypeError: Cannot read properties of undefined).' \
    stage_alpha

  # S2: fix( commit with only INFERRED tags -> WARN fires (never blocks)
  _run "S2-inferred-only-warns" 1 \
    'fix(alpha): add uniqueness guard

## Root cause (evidenced)
INFERRED: a missing uniqueness constraint could allow a double-submit to
insert a duplicate row.' \
    stage_alpha

  # S3: fix( commit with no section, no record -> WARN fires
  _run "S3-no-evidence-warns" 1 \
    'fix(alpha): tighten validation' \
    stage_alpha

  # S4: non-fix commit -> ALLOW, no warn
  _run "S4-non-fix-silent-allow" 0 \
    'feat(alpha): add new capability' \
    stage_alpha

  # S5: merge-context (MERGE_HEAD) -> ALLOW, no warn (skip note instead)
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    echo "0000000000000000000000000000000000000000" > .git/MERGE_HEAD
    local cmd input
    cmd='git commit -m "fix(alpha): merge resolution with no evidence section"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
    rm -f .git/MERGE_HEAD
  )
  _efg_assert_warn "S5-merge-context-skips-no-warn" 0

  # S5b: cherry-pick-context (CHERRY_PICK_HEAD) -> ALLOW, no warn
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    echo "0000000000000000000000000000000000000000" > .git/CHERRY_PICK_HEAD
    local cmd input
    cmd='git commit -m "fix(alpha): replayed cherry-pick with no evidence section"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
    rm -f .git/CHERRY_PICK_HEAD
  )
  _efg_assert_warn "S5b-cherry-pick-context-skips-no-warn" 0

  # S6: record-reference path -- ALLOW, no warn, when a matching
  # fix-root-cause record exists (created via write-review-record.sh in
  # this fixture).
  local WRITE_RECORD="$SELF_DIR/../scripts/write-review-record.sh"
  if [[ -x "$WRITE_RECORD" ]] || [[ -f "$WRITE_RECORD" ]]; then
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      stage_alpha
      OUT=$(bash "$WRITE_RECORD" capture --kind fix-root-cause --reviewer orchestrator \
        --verdict PASS --plan-ref "docs/plans/harness-governance-batch-2026-07-15.md#task-3" \
        --quote "PROVEN via vercel logs -- see incident trace." \
        --file "adapters/claude-code/hooks/alpha.sh" \
        --payload '{"root_cause":{"tag":"PROVEN","evidence":"vercel logs dpl_x line 412"},"blast_radius_bounded":true}' \
        --repo-root "$TMPDIR_ST" 2>&1)
      REC_ID=$(printf '%s\n' "$OUT" | tail -1)
      local cmd input
      cmd=$(printf 'git commit -m "fix(alpha): apply the reviewed fix (%s)"' "$REC_ID")
      input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
      printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
      echo $? > rc.txt
    )
    _efg_assert_warn "S6-record-reference-silent-allow" 0

    # S7: record exists but does NOT cover any staged file -> WARN fires
    (
      cd "$TMPDIR_ST" || exit 99
      git reset -q >/dev/null 2>&1
      mkdir -p adapters/claude-code/hooks
      echo "unrelated" > adapters/claude-code/hooks/beta.sh
      git add adapters/claude-code/hooks/beta.sh
      OUT=$(bash "$WRITE_RECORD" capture --kind fix-root-cause --reviewer orchestrator \
        --verdict PASS --plan-ref "docs/plans/harness-governance-batch-2026-07-15.md#task-3" \
        --quote "PROVEN via logs." \
        --file "adapters/claude-code/hooks/alpha.sh" \
        --payload '{"root_cause":{"tag":"PROVEN"},"blast_radius_bounded":true}' \
        --repo-root "$TMPDIR_ST" 2>&1)
      REC_ID=$(printf '%s\n' "$OUT" | tail -1)
      local cmd input
      cmd=$(printf 'git commit -m "fix(beta): unrelated change citing wrong record (%s)"' "$REC_ID")
      input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
      printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
      echo $? > rc.txt
    )
    _efg_assert_warn "S7-record-no-coverage-warns" 1
  else
    echo "self-test (S6/S7): SKIPPED (write-review-record.sh not found at $WRITE_RECORD)" >&2
  fi

  # S8: fix-trivial: prefix never triggers -> ALLOW, no warn
  _run "S8-fix-trivial-prefix-exempt" 0 \
    'fix-trivial: correct a typo in a comment' \
    stage_alpha

  # S9: structured waiver honored (fresh, both clauses, Files: matches staged) -> no warn banner
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    {
      echo "Purpose: this gate exists to prevent an inferred-not-observed cause from shipping"
      echo "Because: prod DB access is unreachable this session (Supabase 401); the fix is fail-open (feature-flagged off by default)"
      echo "Files: adapters/claude-code/hooks/alpha.sh"
    } > .claude/state/evidence-before-fix-waiver-selftest.txt
    local cmd input
    cmd='git commit -m "fix(alpha): fail-open guard, evidence unreachable"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
    rm -f .claude/state/evidence-before-fix-waiver-selftest.txt
  )
  _efg_assert_warn "S9-waiver-honored-no-warn" 0

  # S10: waiver present but WITHOUT purpose-clause pair -> WARN still fires
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    echo "Files: adapters/claude-code/hooks/alpha.sh" > .claude/state/evidence-before-fix-waiver-weak.txt
    local cmd input
    cmd='git commit -m "fix(alpha): weak waiver attempt"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
    rm -f .claude/state/evidence-before-fix-waiver-weak.txt
  )
  _efg_assert_warn "S10-weak-waiver-warns" 1

  # ---- Parser-reach additions (harness-review REJECT remediation) ----

  # S11: GLUED -m"..." (no space before the quote), no evidence -> WARN fires
  # (proves the parser-reach fix, not just that warn-mode never blocks).
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    local cmd input
    cmd='git commit -m"fix(alpha): glued quote, no evidence at all"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  _efg_assert_warn "S11-glued-m-quote-warns" 1

  # S12: --message= (long-flag, = separator), no evidence -> WARN fires
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    local cmd input
    cmd='git commit --message="fix(alpha): long-flag equals form, no evidence"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  _efg_assert_warn "S12-message-equals-warns" 1

  # S13: multiple -m segments concatenate; a PROVEN+citation line in the
  # SECOND -m paragraph is still found (proves concatenation, not just
  # first-segment reading) -> silent allow, no warn.
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    local cmd input
    cmd='git commit -m "fix(alpha): multi-m subject" -m "## Root cause (evidenced)" -m "PROVEN: adapters/claude-code/hooks/alpha.sh:9 -- see log: TypeError observed in test run"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  _efg_assert_warn "S13-multi-m-concatenates-silent-allow" 0

  # S14: multi-m WITHOUT evidence in any segment -> WARN still fires
  # (confirms multi-m parsing feeds the same evidence check, not a bypass).
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    local cmd input
    cmd='git commit -m "fix(alpha): multi-m subject, no evidence" -m "just a plain second paragraph, nothing evidenced"'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  _efg_assert_warn "S14-multi-m-no-evidence-warns" 1

  # S15: flat-shape CLAUDE_TOOL_INPUT payload branch (env var, not stdin) --
  # exercises the INPUT="${CLAUDE_TOOL_INPUT:-}" path directly, with the
  # flat `.command` shape (no nested tool_input) that observed-errors-gate.sh
  # and gh-merge-canonical-gate.sh both also fall back to.
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    local flat_input
    flat_input=$(jq -n --arg cmd 'git commit -m "fix(alpha): flat-shape payload, no evidence"' '{command:$cmd}')
    CLAUDE_TOOL_INPUT="$flat_input" bash "$SCRIPT_PATH" </dev/null >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  _efg_assert_warn "S15-flat-shape-claude-tool-input-env-warns" 1

  # S16: bare unquoted -m value (single shell word, no evidence) -> WARN fires
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    local cmd input
    cmd='git commit -m fix:no-evidence-single-word'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  _efg_assert_warn "S16-bare-unquoted-m-warns" 1

  # S17: --amend with NO explicit -m/-F/heredoc -- best-effort proxy reads
  # HEAD's current message. HEAD (the "init" commit from setup) has message
  # "init", which does not match fix(/fix: -- proves the proxy reads the
  # right content without asserting evidence behavior on it (a fix(/fix:
  # HEAD message would additionally need staged files, which --amend implies
  # anyway; keeping this scenario to the parser-reach claim: proxy fires,
  # command classifies correctly, no crash).
  (
    cd "$TMPDIR_ST" || exit 99
    git reset -q >/dev/null 2>&1
    stage_alpha
    local cmd input
    cmd='git commit --amend --no-edit'
    input=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    printf '%s' "$input" | bash "$SCRIPT_PATH" >stdout.txt 2>stderr.txt
    echo $? > rc.txt
  )
  _efg_assert_warn "S17-amend-no-explicit-message-proxy-no-warn-on-non-fix-head" 0

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed (of $((PASSED+FAILED)) scenarios)" >&2
  [[ "$FAILED" -eq 0 ]]
}

case "${1:-}" in
  --self-test) run_self_test; exit $? ;;
  *) main ;;
esac
