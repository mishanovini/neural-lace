---
name: harness-review
description: Weekly harness audit — scans for drift, dead links, vaporware, hygiene violations. Writes findings to docs/reviews/YYYY-MM-DD-harness-review.md. Use when the user invokes /harness-review, or when running a scheduled weekly audit of harness state.
---

# harness-review

Periodic self-audit of the harness. Catches drift between what rules and docs
claim versus what exists on disk. Complements live pre-commit enforcement with a
weekly read of the whole surface.

## When to use

Manual invocation: the user types `/harness-review`, or asks for a harness
audit, drift check, or health report.

Scheduled invocation: registered weekly via the `schedule` skill or the
`scheduled-tasks` MCP (see "To run weekly" below).

Do NOT use this skill for:
- Answering questions about a specific rule (read the rule directly)
- Investigating a failing hook (read the hook + its recent invocations)
- Debugging a single plan (use task-verifier or plan-evidence-reviewer)

## What the skill produces

A single file at `docs/reviews/YYYY-MM-DD-harness-review.md` with one section
per check, each labeled PASS or FAIL, and findings listed inline. The file is
appended to (not overwritten) if a review already exists for today — rare, but
supported so a second run in one day doesn't destroy the first.

After writing the file, the skill prints a summary to stdout: total PASS count,
total FAIL count, and the path to the review file.

## Execution

The skill is a bash script that walks the checks in order, accumulates findings,
and writes the output file at the end. Run from the repo root (the working
directory of the Neural Lace harness repo).

```bash
#!/bin/bash
set -u

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
  echo "harness-review: not in a git repo — aborting" >&2
  exit 1
fi
cd "$REPO_ROOT"

TODAY=$(date +%Y-%m-%d)
REVIEW_DIR="$REPO_ROOT/docs/reviews"
REVIEW_FILE="$REVIEW_DIR/${TODAY}-harness-review.md"
mkdir -p "$REVIEW_DIR"

PASS_COUNT=0
FAIL_COUNT=0

# Open the review file. If it already exists for today, append a new run block.
{
  if [[ ! -f "$REVIEW_FILE" ]]; then
    echo "# Harness Review — $TODAY"
    echo ""
    echo "Scheduled audit of harness hygiene, enforcement-map integrity,"
    echo "link validity, rule coverage, and drift between installed config"
    echo "and the repo source of truth."
    echo ""
  else
    echo ""
    echo "---"
    echo ""
    echo "## Additional run at $(date +%H:%M:%S)"
    echo ""
  fi
} > /tmp/harness-review-header.$$
cat /tmp/harness-review-header.$$ >> "$REVIEW_FILE"
rm -f /tmp/harness-review-header.$$

# Helper: write a section header + status.
# Args: $1 = section name, $2 = status (PASS|FAIL), $3..N = findings lines
write_section() {
  local name="$1"
  local status="$2"
  shift 2
  {
    echo "## $name"
    echo ""
    echo "**Status:** $status"
    echo ""
    if [[ $# -gt 0 ]]; then
      echo "**Findings:**"
      echo ""
      for line in "$@"; do
        echo "- $line"
      done
      echo ""
    fi
  } >> "$REVIEW_FILE"
  if [[ "$status" == "PASS" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ==========================================================================
# Check 1: Full-tree hygiene scan
# ==========================================================================
scan_output=$(bash "$REPO_ROOT/adapters/claude-code/hooks/harness-hygiene-scan.sh" --full-tree 2>&1)
scan_rc=$?
if [[ $scan_rc -eq 0 ]]; then
  write_section "1. Full-tree hygiene scan" "PASS"
else
  # Capture the matching lines; keep first 20 for brevity.
  mapfile -t matches < <(echo "$scan_output" | grep -E '^[^[:space:]].+:[0-9]+:' | head -20)
  if [[ ${#matches[@]} -eq 0 ]]; then
    matches=("Scanner exited $scan_rc but no structured matches parsed from output")
  fi
  write_section "1. Full-tree hygiene scan" "FAIL" "${matches[@]}"
fi

# ==========================================================================
# Check 2: Enforcement-map integrity
# ==========================================================================
# Parse enforcement-map-style tables in docs/harness-architecture.md and
# adapters/claude-code/rules/vaporware-prevention.md. Extract all referenced
# file paths under `~/.claude/` or adapters/claude-code/, then verify each
# exists in the repo tree.
enforcement_findings=()
while IFS= read -r line; do
  # Match backtick-wrapped paths that look like filenames under the config tree.
  # Two supported forms:
  #   `~/.claude/<path>` — resolve against adapters/claude-code/ in the repo
  #   `adapters/claude-code/<path>` — resolve directly
  # Extract all such paths from the line.
  while [[ "$line" =~ \`(~/\.claude/[^\`]+|adapters/claude-code/[^\`]+)\` ]]; do
    raw="${BASH_REMATCH[1]}"
    # Strip trailing punctuation.
    raw="${raw%%[[:punct:]]}"
    if [[ "$raw" == ~/.claude/* ]]; then
      rel_path="adapters/claude-code/${raw#~/.claude/}"
    else
      rel_path="$raw"
    fi
    if [[ ! -e "$REPO_ROOT/$rel_path" ]]; then
      enforcement_findings+=("Missing: \`$raw\` (resolved as $rel_path)")
    fi
    # Remove the match to continue the while loop.
    line="${line/\`${BASH_REMATCH[1]}\`/}"
  done
done < <(cat "$REPO_ROOT/docs/harness-architecture.md" \
              "$REPO_ROOT/adapters/claude-code/rules/vaporware-prevention.md" 2>/dev/null \
         | grep -E '\|.*\`(~/\.claude/|adapters/claude-code/)')

# De-duplicate findings
if [[ ${#enforcement_findings[@]} -gt 0 ]]; then
  mapfile -t enforcement_findings < <(printf '%s\n' "${enforcement_findings[@]}" | sort -u)
  write_section "2. Enforcement-map integrity" "FAIL" "${enforcement_findings[@]}"
else
  write_section "2. Enforcement-map integrity" "PASS"
fi

# ==========================================================================
# Check 3: Dead internal links
# ==========================================================================
# Scan .md files in docs/, principles/, adapters/claude-code/ for
# markdown links pointing to other .md paths. Flag paths that don't resolve.
# Skips fenced code blocks (triple-backtick), so example snippets in skill
# files don't produce false positives.
link_findings=()
while IFS= read -r -d '' mdfile; do
  # Skip generated review files and plan/decision/session instances — these
  # may legitimately reference targets not yet committed.
  case "$mdfile" in
    */docs/reviews/*|*/docs/plans/*|*/docs/decisions/*|*/docs/sessions/*) continue ;;
  esac
  # Strip fenced code blocks before grepping — stuff inside ``` ... ``` is
  # illustrative, not live navigation.
  mdbody=$(awk 'BEGIN{fence=0} /^```/{fence=!fence; next} !fence{print}' "$mdfile")
  while IFS= read -r linkpath; do
    [[ -z "$linkpath" ]] && continue
    # Strip any #anchor suffix
    linkpath="${linkpath%%#*}"
    # Skip obvious placeholders: paths with angle-bracket templating or that
    # literally start with "relative-path" (a common illustrative stub).
    case "$linkpath" in
      *\<*|*\>*|relative-path*|path/to/*|your-*) continue ;;
    esac
    # Resolve relative to the markdown file's directory
    mddir=$(dirname "$mdfile")
    resolved="$mddir/$linkpath"
    if [[ ! -e "$resolved" ]]; then
      # Try resolving from repo root as a fallback
      if [[ ! -e "$REPO_ROOT/$linkpath" ]]; then
        rel_mdfile="${mdfile#$REPO_ROOT/}"
        link_findings+=("$rel_mdfile → $linkpath (not found)")
      fi
    fi
  done < <(printf '%s\n' "$mdbody" \
           | grep -oE '\]\([^)]+\.md[^)]*\)' 2>/dev/null \
           | sed -E 's/^\]\(//; s/\)$//' \
           | grep -vE '^https?://')
done < <(find "$REPO_ROOT/docs" "$REPO_ROOT/principles" "$REPO_ROOT/adapters/claude-code" \
              -name '*.md' -type f -print0 2>/dev/null)

if [[ ${#link_findings[@]} -gt 0 ]]; then
  mapfile -t link_findings < <(printf '%s\n' "${link_findings[@]}" | sort -u | head -30)
  write_section "3. Dead internal links" "FAIL" "${link_findings[@]}"
else
  write_section "3. Dead internal links" "PASS"
fi

# ==========================================================================
# Check 4: Rule reference integrity
# ==========================================================================
# Parse adapters/claude-code/CLAUDE.md's "Detailed Protocols" section. Each
# bullet of the form `- \`<name>.md\` — description` must map to an existing
# file at adapters/claude-code/rules/<name>.md.
rule_findings=()
in_protocols_section=0
while IFS= read -r line; do
  if [[ "$line" =~ ^##[[:space:]]+Detailed[[:space:]]Protocols ]]; then
    in_protocols_section=1
    continue
  fi
  if [[ $in_protocols_section -eq 1 && "$line" =~ ^##[[:space:]] ]]; then
    # Hit the next ## section — stop.
    break
  fi
  if [[ $in_protocols_section -eq 1 && "$line" =~ ^-[[:space:]]+\`([^\`]+\.md)\` ]]; then
    rule_name="${BASH_REMATCH[1]}"
    if [[ ! -f "$REPO_ROOT/adapters/claude-code/rules/$rule_name" ]]; then
      rule_findings+=("Missing: adapters/claude-code/rules/$rule_name (referenced in CLAUDE.md Detailed Protocols)")
    fi
  fi
done < "$REPO_ROOT/adapters/claude-code/CLAUDE.md"

if [[ ${#rule_findings[@]} -gt 0 ]]; then
  write_section "4. Rule reference integrity" "FAIL" "${rule_findings[@]}"
else
  write_section "4. Rule reference integrity" "PASS"
fi

# ==========================================================================
# Check 5: Staleness signals
# ==========================================================================
# (a) Rule files whose last-modified date is > 90 days ago
# (b) Decision records with Status: Active and last-modified > 180 days ago
# (c) Plan files still ACTIVE after 30 days
stale_findings=()
NOW=$(date +%s)
NINETY_DAYS=$((90 * 86400))
HUNDRED_EIGHTY_DAYS=$((180 * 86400))
THIRTY_DAYS=$((30 * 86400))

# Rule files > 90 days
while IFS= read -r -d '' rfile; do
  mtime=$(stat -c %Y "$rfile" 2>/dev/null || stat -f %m "$rfile" 2>/dev/null || echo 0)
  if [[ $mtime -gt 0 && $((NOW - mtime)) -gt $NINETY_DAYS ]]; then
    rel="${rfile#$REPO_ROOT/}"
    days=$(( (NOW - mtime) / 86400 ))
    stale_findings+=("Rule not touched in ${days} days: $rel")
  fi
done < <(find "$REPO_ROOT/adapters/claude-code/rules" -maxdepth 1 -name '*.md' -type f -print0 2>/dev/null)

# Plan files still ACTIVE after 30 days
if [[ -d "$REPO_ROOT/docs/plans" ]]; then
  while IFS= read -r -d '' pfile; do
    if grep -qE '^Status:\s*ACTIVE' "$pfile" 2>/dev/null; then
      mtime=$(stat -c %Y "$pfile" 2>/dev/null || stat -f %m "$pfile" 2>/dev/null || echo 0)
      if [[ $mtime -gt 0 && $((NOW - mtime)) -gt $THIRTY_DAYS ]]; then
        rel="${pfile#$REPO_ROOT/}"
        days=$(( (NOW - mtime) / 86400 ))
        stale_findings+=("Plan ACTIVE for ${days} days: $rel")
      fi
    fi
  done < <(find "$REPO_ROOT/docs/plans" -maxdepth 1 -name '*.md' -type f -print0 2>/dev/null)
fi

# Decision records with Status: Active > 180 days
if [[ -d "$REPO_ROOT/docs/decisions" ]]; then
  while IFS= read -r -d '' dfile; do
    if grep -qiE '^Status:\s*Active' "$dfile" 2>/dev/null; then
      mtime=$(stat -c %Y "$dfile" 2>/dev/null || stat -f %m "$dfile" 2>/dev/null || echo 0)
      if [[ $mtime -gt 0 && $((NOW - mtime)) -gt $HUNDRED_EIGHTY_DAYS ]]; then
        rel="${dfile#$REPO_ROOT/}"
        days=$(( (NOW - mtime) / 86400 ))
        stale_findings+=("Decision still Active for ${days} days (reconsider?): $rel")
      fi
    fi
  done < <(find "$REPO_ROOT/docs/decisions" -maxdepth 1 -name '*.md' -type f -print0 2>/dev/null)
fi

if [[ ${#stale_findings[@]} -gt 0 ]]; then
  write_section "5. Staleness signals" "FAIL" "${stale_findings[@]}"
else
  write_section "5. Staleness signals" "PASS"
fi

# ==========================================================================
# Check 6: Ungitignored sensitive file patterns
# ==========================================================================
# Look for files in the tree matching *.local*, *-secret*, *-token*, *.env*
# that are NOT gitignored and NOT already in an allowed example form.
sensitive_findings=()
while IFS= read -r -d '' sfile; do
  rel="${sfile#$REPO_ROOT/}"
  # Check if ignored by git
  if git check-ignore -q "$rel" 2>/dev/null; then
    continue
  fi
  # Skip *.example* files — placeholders are safe
  case "$rel" in
    *.example|*.example.*|*.example*) continue ;;
  esac
  # Skip the pattern files themselves — they legitimately name these
  case "$rel" in
    adapters/claude-code/patterns/*) continue ;;
  esac
  sensitive_findings+=("Ungitignored: $rel")
done < <(find "$REPO_ROOT" -type f \( \
           -name '*.local*' -o \
           -name '*-secret*' -o \
           -name '*-token*' -o \
           -name '*.env*' \
         \) -not -path '*/.git/*' -not -path '*/node_modules/*' -print0 2>/dev/null)

if [[ ${#sensitive_findings[@]} -gt 0 ]]; then
  write_section "6. Ungitignored sensitive files" "FAIL" "${sensitive_findings[@]}"
else
  write_section "6. Ungitignored sensitive files" "PASS"
fi

# ==========================================================================
# Check 7: Scanner denylist health
# ==========================================================================
# Run the scanner's self-test.
selftest_out=$(bash "$REPO_ROOT/adapters/claude-code/hooks/harness-hygiene-scan.sh" --self-test 2>&1)
selftest_rc=$?
scanner_findings=()
if [[ $selftest_rc -ne 0 ]]; then
  scanner_findings+=("Scanner --self-test exited $selftest_rc")
  scanner_findings+=("Output head: $(echo "$selftest_out" | head -3 | tr '\n' ' ')")
fi
# Also sanity-check that the denylist file is non-empty
denylist="$REPO_ROOT/adapters/claude-code/patterns/harness-denylist.txt"
if [[ ! -f "$denylist" ]]; then
  scanner_findings+=("Denylist file missing: $denylist")
elif [[ ! -s "$denylist" ]]; then
  scanner_findings+=("Denylist file is empty")
fi

if [[ ${#scanner_findings[@]} -gt 0 ]]; then
  write_section "7. Scanner denylist health" "FAIL" "${scanner_findings[@]}"
else
  write_section "7. Scanner denylist health" "PASS"
fi

# ==========================================================================
# Check 8: Harness drift between installed config and repo
# ==========================================================================
# For each file in ~/.claude/{agents,rules,docs,hooks,templates,scripts,skills,commands}/,
# check whether it exists in the repo at the corresponding adapter path. Flag
# mismatches by content diff. Non-Windows setups use symlinks and diff will
# typically pass trivially; Windows copies can drift.
drift_findings=()
INSTALLED="$HOME/.claude"
ADAPTER="$REPO_ROOT/adapters/claude-code"
if [[ -d "$INSTALLED" ]]; then
  for subdir in agents rules docs hooks templates scripts skills commands; do
    [[ -d "$INSTALLED/$subdir" ]] || continue
    [[ -d "$ADAPTER/$subdir" ]] || continue
    while IFS= read -r -d '' ifile; do
      base=$(basename "$ifile")
      rfile="$ADAPTER/$subdir/$base"
      if [[ ! -f "$rfile" ]]; then
        drift_findings+=("Missing from repo: $subdir/$base")
      elif ! diff -q "$ifile" "$rfile" > /dev/null 2>&1; then
        drift_findings+=("Differs: $subdir/$base")
      fi
    done < <(find "$INSTALLED/$subdir" -maxdepth 1 -type f -print0 2>/dev/null)
  done
fi

if [[ ${#drift_findings[@]} -gt 0 ]]; then
  mapfile -t drift_findings < <(printf '%s\n' "${drift_findings[@]}" | sort -u)
  total_drift=${#drift_findings[@]}
  # Keep the list readable — top 15 + summary line if more.
  if [[ $total_drift -gt 15 ]]; then
    mapfile -t drift_findings < <(printf '%s\n' "${drift_findings[@]}" | head -15)
    drift_findings+=("... and $((total_drift - 15)) more (total: $total_drift) — run \`diff -r ~/.claude adapters/claude-code\` to see all")
  fi
  write_section "8. Harness drift (installed vs repo)" "FAIL" "${drift_findings[@]}"
else
  write_section "8. Harness drift (installed vs repo)" "PASS"
fi

# ==========================================================================
# Summary
# ==========================================================================
{
  echo ""
  echo "---"
  echo ""
  echo "## Summary"
  echo ""
  echo "- PASS: $PASS_COUNT"
  echo "- FAIL: $FAIL_COUNT"
  echo ""
  if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "**Action:** triage findings above. FAIL sections indicate real drift,"
    echo "dead references, or hygiene regressions. File a backlog entry or fix"
    echo "directly. Re-run \`/harness-review\` after fixes to confirm PASS."
  else
    echo "**All checks passed.** No action required."
  fi
} >> "$REVIEW_FILE"

# Print summary to stdout so the human invoker sees it without opening the file
echo ""
echo "Harness review complete."
echo "  PASS: $PASS_COUNT"
echo "  FAIL: $FAIL_COUNT"
echo "  Output: $REVIEW_FILE"
echo ""

# Exit 0 regardless — findings live in the output file, and the scheduled
# runner should not fail just because the harness has drift. The user reads
# the file; CI (if any) parses it structurally.
exit 0
```

## Interpreting the output

After the skill runs, open `docs/reviews/YYYY-MM-DD-harness-review.md` and
scan the PASS/FAIL labels. Each FAIL section lists specific findings with
enough context to fix directly.

Priority order for triage:

1. **Check 1 (hygiene scan)** — FAIL here means a denylist pattern leaked into
   the tree. Treat as a security issue. Fix before the next commit.
2. **Check 2 (enforcement map integrity)** — FAIL means documentation claims a
   hook/agent/skill exists but it doesn't. Either create the referenced file or
   delete the row in the documentation. Advertising hallucinated enforcement
   is a known anti-pattern.
3. **Check 6 (ungitignored sensitive files)** — FAIL means a `.env` or
   `*-token*` file is tracked by git. Immediately add to `.gitignore` and
   `git rm --cached`.
4. **Check 7 (scanner health)** — FAIL means the scanner itself is broken. All
   other pre-commit gates depend on it. Fix first.
5. **Check 4 (rule reference integrity)** — FAIL means `CLAUDE.md` points at a
   rule file that doesn't exist.
6. **Check 3 (dead links)** — usually low-urgency cleanup but degrades navigation.
7. **Check 8 (drift)** — on non-Windows, FAIL here typically means symlinks got
   broken. On Windows, means install.sh copied and then one side diverged.
8. **Check 5 (staleness)** — informational; review quarterly, not weekly.

## To run weekly

Register a scheduled task once, then the skill runs automatically.

**Via the `schedule` skill (recommended):**

```
/schedule create "Weekly Harness Review" --command "/harness-review" --cron "0 9 * * 1"
```

This runs every Monday at 09:00 local time. Adjust the cron expression to taste.

**Via the `scheduled-tasks` MCP:**

Call `mcp__scheduled-tasks__create_scheduled_task` with:
- `name`: `harness-review-weekly`
- `command`: `/harness-review`
- `schedule`: `0 9 * * 1`

**Reviewing scheduled runs:**

Each week's output is at `docs/reviews/YYYY-MM-DD-harness-review.md`. Open the
most recent one. If there are FAIL sections, address them; if all PASS, file
and continue.

## Honest limitations

- **The drift check (Check 8) requires the installed config to be readable.**
  If the harness is installed somewhere non-standard, edit the `INSTALLED`
  variable in the script.
- **The enforcement-map parser is a regex**, not a full Markdown parser. It
  matches backtick-wrapped paths in pipe-delimited rows. If the architecture
  doc adopts a different table format, the parser needs updating.
- **Dead-link detection follows relative paths from each markdown file's
  directory**, with a fallback to the repo root. Links that use absolute
  filesystem paths will look dead; links to external URLs are deliberately
  not checked.
- **Staleness thresholds (30/90/180 days) are heuristics, not policy.** A rule
  untouched for 100 days may still be correct; the finding is informational.

## Related

- `docs/harness-strategy.md` — the weekly-review cadence this skill implements.
- `adapters/claude-code/hooks/harness-hygiene-scan.sh` — the pre-commit scanner
  this skill wraps with a full-tree scan.
- `adapters/claude-code/rules/harness-maintenance.md` — the drift discipline
  this skill helps detect.
- `adapters/claude-code/agents/harness-reviewer.md` — adversarial review of
  individual harness changes; distinct from this periodic audit.
