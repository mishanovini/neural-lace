#!/bin/bash
# bug-persistence-gate.sh — Stop hook
#
# Scans the session transcript for trigger phrases that indicate a bug,
# gap, or deficiency was identified. For each match, checks whether the
# session produced any corresponding persistence to durable storage:
# docs/backlog.md, docs/reviews/YYYY-MM-DD-*.md, docs/discoveries/
# YYYY-MM-DD-*.md, or docs/findings.md. If trigger phrases are present
# AND no persistence happened, blocks session end with a detailed message.
#
# This is the mechanical enforcement of the bug-persistence rule in
# ~/.claude/rules/testing.md. Rules that depend on the agent remembering
# to follow them are theater; this hook closes the loop.
#
# Escape hatch: the agent can write
#   .claude/state/bugs-attested-YYYY-MM-DD-HHMM.txt
# with one line per trigger-phrase match justifying why it's not a real
# bug (quoted example, rhetorical hypothetical, etc.). If the attestation
# file exists and is more recent than the last trigger phrase, the hook
# allows session end.
#
# Exit codes:
#   0 — session may terminate
#   2 — session is blocked; stderr explains why
#
# Claude Code contract:
#   Stop hooks receive JSON on stdin. We read `transcript_path` from it.
#   If transcript is unavailable, we no-op (can't verify; don't block).
#   On block, we print JSON to stdout with decision: "block" and a
#   reason message. Exit code 2 signals blocking.

set -u

# ============================================================
# --self-test handler — exercise the persistence-target detection
# logic against synthetic git repos. Verifies that EACH of the four
# accepted targets (backlog, reviews/, discoveries/, findings.md)
# satisfies the gate when the transcript contains trigger phrases.
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF_TEST_HOOK" ]]; then
    echo "self-test: cannot resolve own path" >&2
    exit 2
  fi

  PASSED=0
  FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t bug-persistence)
  if [[ -z "$TMPROOT" ]] || [[ ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  # Helper: build a fake transcript file containing a trigger phrase, set
  # up a synthetic repo with the named persistence target modified or
  # unmodified, then invoke the hook. Returns the hook's exit code.
  #
  # Args: $1 = scenario label
  #       $2 = persistence target type:
  #            "backlog"      => modify docs/backlog.md
  #            "review"       => add docs/reviews/2026-05-04-test.md
  #            "discovery"    => add docs/discoveries/2026-05-04-test.md
  #            "findings"     => modify docs/findings.md
  #            "none"         => no persistence (expects BLOCK)
  _run_scenario() {
    local label="$1" persistence="$2"
    local repo="$TMPROOT/$label"
    mkdir -p "$repo"
    (
      cd "$repo" || exit 99
      git init -q 2>/dev/null || true
      git config user.email "test@example.com" 2>/dev/null
      git config user.name "Test" 2>/dev/null
      git config commit.gpgsign false 2>/dev/null

      mkdir -p docs/reviews docs/discoveries

      # Make a marker commit so HEAD exists. We use an UNRELATED file so
      # `git log -- docs/backlog.md docs/findings.md docs/reviews/* docs/discoveries/*`
      # does NOT see this commit (which would otherwise spuriously satisfy
      # the recent-touches branch of the persistence check).
      echo "init" > .marker
      git add .marker 2>/dev/null
      git commit -q -m "init" 2>/dev/null

      # Apply the persistence change. Each target lives only in the
      # working tree (not committed) so the gate's `status --porcelain`
      # branch is what triggers the PERSISTED detection.
      case "$persistence" in
        backlog)
          # backlog.md tracked? No — first need to make `git status` show it.
          # We create the file untracked-then-add or rely on `status --porcelain`
          # which DOES report untracked files when a path is given. But
          # the hook uses `git status --porcelain docs/backlog.md` which
          # reports the file as untracked (`??`) if it's there but not tracked.
          echo "- new bug observed" > docs/backlog.md
          ;;
        review)
          echo "# Review" > docs/reviews/2026-05-04-test.md
          ;;
        discovery)
          echo "# Discovery" > docs/discoveries/2026-05-04-test.md
          ;;
        findings)
          cat > docs/findings.md <<'NL'
# Findings

### NL-FINDING-002 — fresh entry

- **Severity:** info
- **Scope:** unit
- **Source:** orchestrator
- **Location:** somewhere:1
- **Status:** open
- **Description:** Synthetic finding entry written this session.
NL
          ;;
        none)
          : # no-op
          ;;
      esac

      # Synthesize a minimal JSONL transcript containing a trigger phrase.
      cat > transcript.jsonl <<'JSONL'
{"role": "assistant", "content": "We should also handle the X case. Let me flag this for follow-up."}
JSONL

      local input
      input=$(printf '{"transcript_path":"%s"}' "$repo/transcript.jsonl")
      printf '%s' "$input" | bash "$SELF_TEST_HOOK" >stdout.txt 2>stderr.txt
      echo $? > rc.txt
    )
    cat "$repo/rc.txt" 2>/dev/null || echo 99
  }

  # ---- Scenario 1: PASS-with-backlog-edit ----
  RC=$(_run_scenario s1 "backlog")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (1) PASS-with-backlog-edit: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (1) PASS-with-backlog-edit: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s1/stderr.txt" >&2 2>/dev/null || true
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 2: PASS-with-review-file ----
  RC=$(_run_scenario s2 "review")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (2) PASS-with-review-file: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (2) PASS-with-review-file: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s2/stderr.txt" >&2 2>/dev/null || true
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 3: PASS-with-discovery-file ----
  RC=$(_run_scenario s3 "discovery")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (3) PASS-with-discovery-file: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (3) PASS-with-discovery-file: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s3/stderr.txt" >&2 2>/dev/null || true
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 4: PASS-with-findings-entry (NEW for Phase 1d-C-3) ----
  RC=$(_run_scenario s4 "findings")
  if [[ "$RC" == "0" ]]; then
    echo "self-test (4) PASS-with-findings-entry: PASS (rc=$RC, expected 0)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (4) PASS-with-findings-entry: FAIL (rc=$RC, expected 0)" >&2
    cat "$TMPROOT/s4/stderr.txt" >&2 2>/dev/null || true
    FAILED=$((FAILED+1))
  fi

  # ---- Scenario 5: BLOCK-no-persistence ----
  RC=$(_run_scenario s5 "none")
  if [[ "$RC" == "2" ]]; then
    echo "self-test (5) BLOCK-no-persistence: PASS (rc=$RC, expected 2; correctly blocked)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test (5) BLOCK-no-persistence: FAIL (rc=$RC, expected 2)" >&2
    FAILED=$((FAILED+1))
  fi

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 5 scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi

# Read stdin JSON (Claude Code provides it)
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

# Locate transcript. Field name varies across Claude Code versions; try both.
TRANSCRIPT_PATH=""
if [[ -n "$INPUT" ]]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // .hook_event_name // empty' 2>/dev/null || echo "")
fi

# If we can't find a transcript, no-op — better to let session end than
# to block falsely.
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# Trigger phrases. Grouped by category for readability.
# We match case-insensitively but require word boundaries where sensible
# to avoid matching legitimate narrative text.
TRIGGER_PATTERNS=(
  # Deferral phrases
  'for next session'
  'll (document|add|fix|address) .* later'
  'as a follow[- ]up'
  'ideally we.?d'
  'we should also'
  'this is out of scope'
  'backlog item'
  'will (need to|have to) (add|fix|document)'
  # Gap-observation phrases
  'turns out .{0,40}(doesn.?t|don.?t|not) work'
  'this is missing'
  'we don.?t have'
  'let me flag'
  'worth noting'
  'note to self'
  'known (issue|bug|limitation|gap)'
  # Discovery phrases
  'found a bug'
  'there.?s an issue'
  'something.?s wrong with'
)

# Scan the transcript. We extract both the matching phrase and a ~60-char
# surrounding context so the user can see what was actually said.
MATCHES_FILE=$(mktemp)
trap 'rm -f "$MATCHES_FILE"' EXIT

# Read transcript text. Claude Code transcripts are JSONL (one JSON object
# per line, each with a text field). We concatenate all text content for
# scanning.
TRANSCRIPT_TEXT=$(mktemp)
trap 'rm -f "$MATCHES_FILE" "$TRANSCRIPT_TEXT"' EXIT

# Extract text from JSONL transcript. If jq isn't available or format
# differs, fall back to treating the file as plain text.
if command -v jq >/dev/null 2>&1; then
  jq -r '.content // .text // .message.content // empty' "$TRANSCRIPT_PATH" 2>/dev/null > "$TRANSCRIPT_TEXT" || cat "$TRANSCRIPT_PATH" > "$TRANSCRIPT_TEXT"
else
  cat "$TRANSCRIPT_PATH" > "$TRANSCRIPT_TEXT"
fi

# Only scan messages from the assistant (Claude's own words). The user
# may quote trigger phrases, include them in example text, or describe
# them rhetorically — those aren't bug-identifications. If we can
# distinguish roles, scan assistant-only. If not, scan everything and
# rely on the attestation escape hatch.
ASSISTANT_TEXT=$(mktemp)
trap 'rm -f "$MATCHES_FILE" "$TRANSCRIPT_TEXT" "$ASSISTANT_TEXT"' EXIT
if command -v jq >/dev/null 2>&1; then
  jq -r 'select(.role == "assistant" or .message.role == "assistant") | (.content // .text // .message.content // empty)' "$TRANSCRIPT_PATH" 2>/dev/null > "$ASSISTANT_TEXT" || true
fi
# If the assistant-only filter produced content, use it. Otherwise scan all.
if [[ -s "$ASSISTANT_TEXT" ]]; then
  SCAN_TARGET="$ASSISTANT_TEXT"
else
  SCAN_TARGET="$TRANSCRIPT_TEXT"
fi

MATCH_COUNT=0
for pattern in "${TRIGGER_PATTERNS[@]}"; do
  # grep -P for Perl regex, -i for case-insensitive, -o for match-only.
  # Capture one line of context before + after via -B1 -A1. Limit per
  # pattern to the first 3 matches to avoid noise.
  while IFS= read -r line; do
    MATCH_COUNT=$((MATCH_COUNT + 1))
    echo "  • ${line:0:140}" >> "$MATCHES_FILE"
    [[ "$MATCH_COUNT" -ge 10 ]] && break
  done < <(grep -iE "$pattern" "$SCAN_TARGET" 2>/dev/null | head -n 3)
  [[ "$MATCH_COUNT" -ge 10 ]] && break
done

# If no trigger phrases, nothing to enforce.
if [[ "$MATCH_COUNT" -eq 0 ]]; then
  exit 0
fi

# Check whether the session persisted bugs anywhere. Two possibilities:
#   1. docs/backlog.md modified (staged, unstaged, or in a recent commit)
#   2. A new docs/reviews/YYYY-MM-DD-*.md file was added
#
# We look across all plausible backlog paths (top level + one subdirectory
# deep, matching pre-stop-verifier.sh's path-discovery pattern) so the
# hook works in monorepos.

PERSISTED=0

check_persisted_for() {
  local root="$1"
  # Unstaged or staged change to backlog.md
  if git -C "$root" status --porcelain docs/backlog.md 2>/dev/null | grep -q .; then
    PERSISTED=1
    return
  fi
  # Unstaged or staged change to findings.md (Phase 1d-C-3, 2026-05-04;
  # see ~/.claude/rules/findings-ledger.md and Decision 019).
  if git -C "$root" status --porcelain docs/findings.md 2>/dev/null | grep -q .; then
    PERSISTED=1
    return
  fi
  # New review file (untracked)
  if git -C "$root" ls-files --others --exclude-standard docs/reviews/ 2>/dev/null | grep -qE '^docs/reviews/[0-9]{4}-[0-9]{2}-[0-9]{2}-'; then
    PERSISTED=1
    return
  fi
  # Modified/added review file in working tree
  if git -C "$root" status --porcelain docs/reviews/ 2>/dev/null | grep -qE 'docs/reviews/[0-9]{4}-[0-9]{2}-[0-9]{2}-'; then
    PERSISTED=1
    return
  fi
  # New discovery file (untracked) — see ~/.claude/rules/discovery-protocol.md
  if git -C "$root" ls-files --others --exclude-standard docs/discoveries/ 2>/dev/null | grep -qE '^docs/discoveries/[0-9]{4}-[0-9]{2}-[0-9]{2}-'; then
    PERSISTED=1
    return
  fi
  # Modified/added discovery file in working tree
  if git -C "$root" status --porcelain docs/discoveries/ 2>/dev/null | grep -qE 'docs/discoveries/[0-9]{4}-[0-9]{2}-[0-9]{2}-'; then
    PERSISTED=1
    return
  fi
  # Commits ANY branch touched these paths in the last ~6 hours (the
  # session window). This catches the case where persistence was done
  # on a feature branch that isn't the current HEAD — the bugs are
  # recorded, they just live on a different branch that will be merged
  # separately. `--all` picks up every ref, not just current branch.
  local recent_touches
  recent_touches=$(git -C "$root" log --all --since="6 hours ago" \
    --pretty=format:'%H' -- docs/backlog.md docs/findings.md 'docs/reviews/*' 'docs/discoveries/*' 2>/dev/null | head -1)
  if [[ -n "$recent_touches" ]]; then
    PERSISTED=1
    return
  fi
  # Reflog: any commit on any branch in the session window that touched
  # the persistence paths. Belt-and-suspenders for detached HEAD or
  # worktree edge cases.
  local reflog_touches
  reflog_touches=$(git -C "$root" reflog --since="6 hours ago" --pretty=format:'%H' 2>/dev/null | \
    while read -r sha; do
      [[ -z "$sha" ]] && continue
      if git -C "$root" diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null | \
         grep -qE '^docs/backlog\.md$|^docs/findings\.md$|^docs/reviews/[0-9]{4}-[0-9]{2}-[0-9]{2}-|^docs/discoveries/[0-9]{4}-[0-9]{2}-[0-9]{2}-'; then
        echo "$sha"
        break
      fi
    done)
  if [[ -n "$reflog_touches" ]]; then
    PERSISTED=1
    return
  fi
}

# Check current repo root + one level of subdirs (handles monorepos)
check_persisted_for .
if [[ "$PERSISTED" -eq 0 ]]; then
  for sub in */; do
    [[ -d "$sub.git" ]] || [[ -d ".git" ]] || continue
    check_persisted_for "${sub%/}"
    [[ "$PERSISTED" -eq 1 ]] && break
  done
fi

# Attestation escape hatch — agent has explicitly declared these matches
# are not real bugs (quoted examples, hypothetical, etc.).
ATTEST_DIR=".claude/state"
if [[ -d "$ATTEST_DIR" ]]; then
  # Most recent attestation file (if any) within the last 1 hour
  if find "$ATTEST_DIR" -type f -name 'bugs-attested-*.txt' -newermt '1 hour ago' 2>/dev/null | grep -q .; then
    PERSISTED=1
  fi
fi

if [[ "$PERSISTED" -eq 1 ]]; then
  exit 0
fi

# Trigger phrases present + no persistence + no attestation = block
cat >&2 <<MSG
================================================================
BUG-PERSISTENCE GATE — BLOCKED
================================================================

This session mentioned bugs / gaps / deficiencies using trigger
phrases, but did NOT persist any of them to docs/backlog.md,
docs/reviews/YYYY-MM-DD-<slug>.md, docs/discoveries/YYYY-MM-DD-<slug>.md,
or docs/findings.md. See rule in ~/.claude/rules/testing.md (Bug
Persistence section).

Trigger phrases detected (up to 10):

$(cat "$MATCHES_FILE")

Before the session can end, do ONE of:

  1. Add bullet(s) to docs/backlog.md under the appropriate P0/P1/P2
     section. Each bullet must include enough detail that a future
     session could pick it up cold.

  2. Create docs/reviews/YYYY-MM-DD-<slug>.md and list every bug with
     evidence + fix path. Use this for batches of findings from a
     testing / audit pass.

  3. Create docs/discoveries/YYYY-MM-DD-<slug>.md with the discovery
     protocol format (see ~/.claude/rules/discovery-protocol.md). Use
     this for mid-process realizations that aren't bug-shaped:
     architectural learnings, scope expansions, dependency surprises,
     performance/failure-mode/process/user-experience discoveries.
     The discovery file structure (frontmatter type, status, auto_applied,
     etc.) is documented in the rule.

  4. Add a structured entry to docs/findings.md per the locked six-field
     schema (Decision 019; see ~/.claude/rules/findings-ledger.md and the
     template at ~/.claude/templates/findings-template.md). Use this for
     class-aware observations from gates / adversarial-review agents /
     builder mid-session discoveries that warrant a tracked disposition
     (open → in-progress → dispositioned-act/defer/accept → closed).
     The findings-ledger schema gate validates entries on commit.

  5. If the matches are false positives (quoted examples, rhetorical,
     etc.), create .claude/state/bugs-attested-YYYY-MM-DD-HHMM.txt
     with one line per false-positive justifying why. Create the
     state directory if it doesn't exist; it's gitignored.

See also: ~/.claude/rules/planning.md "Identifying a gap = writing a
backlog entry, in the same response" — the same principle applies to
bugs surfaced during execution.

================================================================
MSG

# JSON decision for Claude Code
cat <<'JSON'
{"decision": "block", "reason": "Bug-persistence gate: trigger phrases detected without corresponding edit to docs/backlog.md, docs/reviews/YYYY-MM-DD-*.md, docs/discoveries/YYYY-MM-DD-*.md, or docs/findings.md. See stderr for details and escape hatches."}
JSON

exit 2
