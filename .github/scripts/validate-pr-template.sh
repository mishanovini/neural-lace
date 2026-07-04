#!/usr/bin/env bash
# PR Template Validator Library
#
# Shared validation logic sourced by:
#   - .github/workflows/pr-template-check.yml (CI side)
#   - adapters/claude-code/git-hooks/pre-push-pr-template.sh (local side)
#
# Both call sites must use identical regex patterns and stderr messages so
# users see the same diagnostic in both contexts.
#
# Bash 3.2+ compatible (macOS default). Avoids associative arrays, mapfile,
# ${var,,} lowercase expansion, and &>> append-redirect.
#
# Usage (from a calling script):
#   source .github/scripts/validate-pr-template.sh
#   PR_BODY="$(cat <input>)"
#   if validate_pr_body "$PR_BODY"; then
#     echo "[pr-template] verdict: PASS"
#   else
#     exit 1
#   fi

# --- Constants ---------------------------------------------------------------

# The exact section heading the workflow looks for. Case-sensitive,
# anchored to start of line. The literal "?" is escaped in regex contexts.
PR_TEMPLATE_MECHANISM_HEADING='## What mechanism would have caught this?'

# Placeholder text that must NOT appear in the filled mechanism section.
# Literal substring match (no regex), so byte-for-byte equality required.
PR_TEMPLATE_PLACEHOLDER='<mechanism answer — replace this bracketed text>'

# Minimum substantive rationale length for the (c) "no mechanism" answer form.
PR_TEMPLATE_RATIONALE_MIN_CHARS=40

# --- Diagnostic-evidence section constants ----------------------------------

# Heading for the diagnostic-evidence section. Case-sensitive, anchored to
# start of line via grep -Fxq. The full sub-title is part of the match so
# a PR that pastes only "## Primary evidence" (without the parenthetical)
# does not falsely satisfy the heading check.
PR_TEMPLATE_EVIDENCE_HEADING='## Primary evidence (required for any sweep / class-fix / refactor PR)'

# The four required sub-headings under the Primary evidence section. Each
# must have substantive non-placeholder content beneath it.
PR_TEMPLATE_EVIDENCE_SUBHEADINGS=(
  '### What runtime/log evidence did you pull?'
  '### What did the evidence show?'
  '### What hypothesis did you test BEFORE writing the fix?'
  '### What refutation criteria would have shown the hypothesis was wrong?'
)

# Per-sub-heading minimum substantive char count. The threshold is the same
# as the mechanism rationale's (deliberately — substantive primary evidence
# is at least as effortful as a no-mechanism rationale).
PR_TEMPLATE_EVIDENCE_SUBSECTION_MIN_CHARS=40

# Opt-out marker. Pattern matches `[evidence-exempt: <reason>]` anywhere in
# the PR body. The reason must be ≥ 20 substantive chars to count.
PR_TEMPLATE_EVIDENCE_EXEMPT_RE='\[evidence-exempt:[[:space:]]*([^]]*)\]'
PR_TEMPLATE_EVIDENCE_EXEMPT_MIN_CHARS=20

# PR-title pattern that requires the diagnostic-evidence section. Case-
# insensitive substring match. A PR whose title contains any of these tokens
# is claiming to fix a recurring class and must show primary evidence (or
# explicit opt-out).
PR_TEMPLATE_EVIDENCE_TITLE_TRIGGERS='(^|[^a-z])(fix:|sweep|class-sweep|refactor)([^a-z]|$)'

# --- Functions ---------------------------------------------------------------

# emit_failure_message <category> <detail>
# Writes the canonical failure message to stderr.
emit_failure_message() {
  local category="$1"
  local detail="$2"
  case "$category" in
    section_missing)
      printf '[pr-template] FAIL: required section heading "%s" not found in PR body\n' "$PR_TEMPLATE_MECHANISM_HEADING" >&2
      ;;
    placeholder_present)
      printf '[pr-template] FAIL: placeholder text "%s" still present; section was not filled in\n' "$PR_TEMPLATE_PLACEHOLDER" >&2
      ;;
    no_answer_form)
      printf '[pr-template] FAIL: no answer form selected; expected one of "### a) Existing catalog entry", "### b) New catalog entry proposed", or "### c) No mechanism — accepted residual risk"\n' >&2
      ;;
    rationale_short)
      printf '[pr-template] FAIL: "no mechanism" option requires ≥%d chars of substantive rationale (got %s chars)\n' "$PR_TEMPLATE_RATIONALE_MIN_CHARS" "$detail" >&2
      ;;
    evidence_section_missing)
      printf '[pr-template] FAIL: PR title matches sweep/class-fix/refactor pattern but "%s" section is missing. Either fill in the four sub-sections (runtime/log evidence, what it showed, hypothesis tested, refutation criteria) per diagnosis.md DIAGNOSTIC-FIRST PROTOCOL, or add an opt-out marker `[evidence-exempt: <reason>]` (≥%d chars) anywhere in the PR body.\n' "$PR_TEMPLATE_EVIDENCE_HEADING" "$PR_TEMPLATE_EVIDENCE_EXEMPT_MIN_CHARS" >&2
      ;;
    evidence_subsection_missing)
      printf '[pr-template] FAIL: Primary evidence sub-section under-substance: %s\n' "$detail" >&2
      ;;
    evidence_exempt_too_short)
      printf '[pr-template] FAIL: `[evidence-exempt: ...]` marker found but rationale is shorter than %d chars (got %s chars). Add a substantive reason or fill the Primary evidence section properly.\n' "$PR_TEMPLATE_EVIDENCE_EXEMPT_MIN_CHARS" "$detail" >&2
      ;;
    *)
      printf '[pr-template] FAIL: %s\n' "$detail" >&2
      ;;
  esac
}

# find_section_heading <pr_body>
# Returns 0 if the canonical mechanism heading is present in the body
# (case-sensitive, anchored to start of line). Returns 1 otherwise.
find_section_heading() {
  local body="$1"
  # grep with -F (literal), -x (full line match) anchors implicitly per line.
  printf '%s\n' "$body" | grep -Fxq "$PR_TEMPLATE_MECHANISM_HEADING"
}

# extract_section_content <pr_body>
# Prints the content from after the mechanism heading to the next `^## `
# heading or EOF. Used to scope placeholder + answer-form detection to the
# mechanism section only.
extract_section_content() {
  local body="$1"
  printf '%s\n' "$body" | awk -v heading="$PR_TEMPLATE_MECHANISM_HEADING" '
    BEGIN { in_section = 0 }
    {
      if (in_section && $0 ~ /^## /) {
        # Reached next top-level heading. Stop.
        exit 0
      }
      if (in_section) {
        print
      }
      if ($0 == heading) {
        in_section = 1
      }
    }
  '
}

# detect_placeholder <content>
# Returns 0 if the literal placeholder substring is found in the content,
# 1 otherwise.
#
# Per the template's documented contract (PULL_REQUEST_TEMPLATE.md line 11 and
# ~/.claude/rules/planning.md): "leave the other sub-headings present (they
# document the option set) but their bracketed placeholder text may stay."
# Callers must scope `content` to the SELECTED sub-section only — leftover
# placeholders under the two unselected sub-headings are expected and OK.
detect_placeholder() {
  local content="$1"
  # Use grep -F for literal (no regex) substring match.
  printf '%s\n' "$content" | grep -Fq "$PR_TEMPLATE_PLACEHOLDER"
}

# extract_selected_subsection <section_content> <form>
# Prints content under the selected ### a) / ### b) / ### c) sub-heading,
# stopping at the next ### sub-heading or EOF. Used to scope the
# placeholder check to the sub-section the author claimed to fill in.
extract_selected_subsection() {
  local content="$1"
  local form="$2"
  local pattern
  case "$form" in
    a) pattern='^### a[)] Existing catalog entry' ;;
    b) pattern='^### b[)] New catalog entry proposed' ;;
    c) pattern='^### c[)] No mechanism' ;;
    *) return 0 ;;
  esac
  printf '%s\n' "$content" | awk -v pat="$pattern" '
    BEGIN { in_sub = 0 }
    {
      if (in_sub && $0 ~ /^### /) {
        exit 0
      }
      if (in_sub) {
        print
      }
      if ($0 ~ pat) {
        in_sub = 1
      }
    }
  '
}

# detect_ai_prose_form <section_content>
# Echoes one of: a, b, c, NONE
# Detects the AI-natural prose form where the author writes the answer as
# a paragraph beginning with "(a)", "(b)", or "(c)" (optionally wrapped in
# **bold**), instead of using the strict "### a)" / "### b)" / "### c)"
# sub-heading scaffold.
#
# Examples that match:
#   (b) New catalog entry proposed. This is a new failure-class candidate...
#   **(c) No mechanism — accepted residual risk.** The original DEC-A...
#   **(b) New catalog entries proposed.** NL-FINDING-009/010 in...
#
# The first such line in the section wins (mirrors detect_answer_form's
# first-sub-heading-with-content semantics). For the form to count, the
# section must also have substantive non-placeholder content (≥ 30 chars
# after the form-marker line is stripped), guarding against a body that
# contains just "(b)" with nothing after.
detect_ai_prose_form() {
  local content="$1"
  local letter
  # First line starting with optional whitespace, optional **, then (a|b|c),
  # then whitespace OR end-of-line. Bash 3.2 compatible — no PCRE.
  letter=$(printf '%s\n' "$content" | awk '
    /^[[:space:]]*\**\([abc]\)([[:space:]]|$)/ {
      # Strip leading whitespace + optional ** then capture letter.
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/^\*+/, "", line)
      # line now starts with (x)...
      letter = substr(line, 2, 1)
      print letter
      exit 0
    }
  ')
  if [[ -z "$letter" ]]; then
    echo "NONE"
    return
  fi
  # Verify substantive content in the section beyond the form-marker line.
  local substantive_chars
  substantive_chars=$(printf '%s\n' "$content" | awk -v placeholder="$PR_TEMPLATE_PLACEHOLDER" '
    BEGIN { total = 0 }
    {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      # Skip empty lines, placeholder lines, and lines that are JUST the
      # form-marker like "(b)" or "**(b)**" with no surrounding content.
      if (line == "") next
      if (index(line, placeholder) > 0) next
      total += length(line)
    }
    END { print total }
  ')
  if [[ "$substantive_chars" -lt 30 ]]; then
    echo "NONE"
    return
  fi
  echo "$letter"
}

# detect_answer_form <section_content>
# Echoes one of: a, b, c, NONE
# Detects which `### a)`, `### b)`, or `### c)` sub-heading has substantive
# content (any non-whitespace) below it before the next `### ` or EOF.
# A sub-heading is "selected" if it has any non-whitespace content (other
# than the placeholder string) below it.
detect_answer_form() {
  local content="$1"
  printf '%s\n' "$content" | awk -v placeholder="$PR_TEMPLATE_PLACEHOLDER" '
    BEGIN { current = ""; selected = ""; }
    /^### a\) Existing catalog entry/ { check_selected(); current = "a"; content_chars = 0; next }
    /^### b\) New catalog entry proposed/ { check_selected(); current = "b"; content_chars = 0; next }
    /^### c\) No mechanism/ { check_selected(); current = "c"; content_chars = 0; next }
    {
      if (current != "" && selected == "") {
        # Strip whitespace and the placeholder string for substance check.
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line != "" && index(line, placeholder) == 0) {
          content_chars += length(line)
        }
      }
    }
    function check_selected() {
      if (current != "" && content_chars > 0 && selected == "") {
        selected = current
      }
    }
    END {
      check_selected()
      if (selected == "") {
        print "NONE"
      } else {
        print selected
      }
    }
  '
}

# validate_rationale_length <section_content>
# For the (c) "no mechanism" answer form, count chars of non-whitespace
# substantive content under the `### c)` sub-heading. Echoes the count.
validate_rationale_length() {
  local content="$1"
  printf '%s\n' "$content" | awk -v placeholder="$PR_TEMPLATE_PLACEHOLDER" '
    BEGIN { in_c = 0; total = 0 }
    /^### c\) No mechanism/ { in_c = 1; next }
    /^### / {
      # Reached another sub-heading; stop counting.
      in_c = 0
    }
    {
      if (in_c) {
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line != "" && index(line, placeholder) == 0) {
          total += length(line)
        }
      }
    }
    END { print total }
  '
}

# validate_rationale_length_prose <section_content>
# Prose-form variant for the (c) answer when written as natural paragraphs
# instead of under a "### c)" sub-heading. Counts all substantive non-
# placeholder non-empty chars in the section (since prose form has no
# sub-section boundary to scope to). Echoes the count.
validate_rationale_length_prose() {
  local content="$1"
  printf '%s\n' "$content" | awk -v placeholder="$PR_TEMPLATE_PLACEHOLDER" '
    BEGIN { total = 0 }
    {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") next
      if (index(line, placeholder) > 0) next
      total += length(line)
    }
    END { print total }
  '
}

# --- Diagnostic-evidence functions ------------------------------------------

# pr_title_requires_evidence <pr_title>
# Returns 0 if the title matches the fix/sweep/class-sweep/refactor pattern
# (case-insensitive). Returns 1 otherwise. Empty title returns 1.
pr_title_requires_evidence() {
  local title="$1"
  [[ -z "$title" ]] && return 1
  # Use grep -i for case-insensitive match. The PR_TEMPLATE_EVIDENCE_TITLE_TRIGGERS
  # pattern uses word-boundary-ish anchors (start-of-line OR non-letter) to
  # avoid matching "prefix:" in unrelated tokens.
  if printf '%s\n' "$title" | grep -iqE "$PR_TEMPLATE_EVIDENCE_TITLE_TRIGGERS"; then
    return 0
  fi
  return 1
}

# detect_evidence_exemption <pr_body>
# Echoes the substantive char count of the [evidence-exempt: <reason>] marker
# if one is present, or 0 if the marker is absent. Used by the validator to
# decide whether the PR opted out of the evidence requirement.
detect_evidence_exemption() {
  local body="$1"
  # Extract the reason text from the first matching marker.
  # awk avoids bash-version-sensitive regex capture groups.
  printf '%s\n' "$body" | awk '
    BEGIN { found = 0; chars = 0 }
    {
      if (!found && match($0, /\[evidence-exempt:[[:space:]]*[^]]*\]/)) {
        m = substr($0, RSTART, RLENGTH)
        # Strip the prefix and the trailing ]
        sub(/^\[evidence-exempt:[[:space:]]*/, "", m)
        sub(/\][[:space:]]*$/, "", m)
        # Count non-whitespace chars in the reason.
        gsub(/[[:space:]]/, "", m)
        chars = length(m)
        found = 1
      }
    }
    END { print chars }
  '
}

# extract_evidence_section <pr_body>
# Prints the content from after the Primary evidence heading to the next
# `^## ` heading or EOF.
extract_evidence_section() {
  local body="$1"
  printf '%s\n' "$body" | awk -v heading="$PR_TEMPLATE_EVIDENCE_HEADING" '
    BEGIN { in_section = 0 }
    {
      if (in_section && $0 ~ /^## /) {
        exit 0
      }
      if (in_section) {
        print
      }
      if ($0 == heading) {
        in_section = 1
      }
    }
  '
}

# validate_evidence_subsections <evidence_section>
# Returns 0 if all four required sub-sections have ≥ N chars of substantive
# (non-placeholder, non-whitespace) content. Echoes the failing sub-section
# name to stderr on the first failure.
validate_evidence_subsections() {
  local section="$1"
  local sub
  for sub in "${PR_TEMPLATE_EVIDENCE_SUBHEADINGS[@]}"; do
    local sub_content
    sub_content=$(printf '%s\n' "$section" | awk -v target="$sub" '
      BEGIN { in_sub = 0 }
      {
        if (in_sub && $0 ~ /^### /) {
          exit 0
        }
        if (in_sub) {
          print
        }
        if ($0 == target) {
          in_sub = 1
        }
      }
    ')
    # Count substantive (non-whitespace, non-placeholder) chars.
    local chars
    chars=$(printf '%s\n' "$sub_content" | awk '
      BEGIN { total = 0 }
      {
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line == "") next
        # Skip lines that look like the template placeholder.
        if (line ~ /<replace this bracketed text/) next
        total += length(line)
      }
      END { print total }
    ')
    if [[ "$chars" -lt "$PR_TEMPLATE_EVIDENCE_SUBSECTION_MIN_CHARS" ]]; then
      printf '%s (got %s chars, threshold %d)' "$sub" "$chars" "$PR_TEMPLATE_EVIDENCE_SUBSECTION_MIN_CHARS"
      return 1
    fi
  done
  return 0
}

# validate_evidence <pr_body> <pr_title>
# Top-level diagnostic-evidence check. Returns 0 if the PR is either (a) not
# title-triggered, (b) has a substantive [evidence-exempt: ...] marker, or
# (c) has all four Primary-evidence sub-sections filled. Returns 1 otherwise.
validate_evidence() {
  local body="$1"
  local title="$2"
  if ! pr_title_requires_evidence "$title"; then
    printf '[pr-template] evidence check: SKIP (title does not match sweep/fix/refactor pattern)\n'
    return 0
  fi
  printf '[pr-template] evidence check: REQUIRED (title matches: %s)\n' "$title"

  # Opt-out path — check before the section requirement so a thin marker
  # short-circuits the heavier check.
  local exempt_chars
  exempt_chars=$(detect_evidence_exemption "$body")
  if [[ "$exempt_chars" -gt 0 ]]; then
    if [[ "$exempt_chars" -lt "$PR_TEMPLATE_EVIDENCE_EXEMPT_MIN_CHARS" ]]; then
      emit_failure_message evidence_exempt_too_short "$exempt_chars"
      printf '[pr-template] verdict: FAIL\n'
      return 1
    fi
    printf '[pr-template] evidence check: OPT-OUT (%s chars of rationale)\n' "$exempt_chars"
    return 0
  fi

  # Section-presence check.
  if ! printf '%s\n' "$body" | grep -Fxq "$PR_TEMPLATE_EVIDENCE_HEADING"; then
    emit_failure_message evidence_section_missing
    printf '[pr-template] verdict: FAIL\n'
    return 1
  fi
  printf '[pr-template] evidence section heading found\n'

  local section
  section=$(extract_evidence_section "$body")
  local sub_failure
  if ! sub_failure=$(validate_evidence_subsections "$section"); then
    emit_failure_message evidence_subsection_missing "$sub_failure"
    printf '[pr-template] verdict: FAIL\n'
    return 1
  fi

  printf '[pr-template] evidence check: PASS (all four sub-sections substantive)\n'
  return 0
}

# validate_pr_body <pr_body> [pr_title]
# Top-level validator. Returns 0 if the body passes all checks, 1 otherwise.
# Emits stdout progress logs and stderr canonical failure messages.
#
# When `pr_title` is supplied (or PR_TITLE env is set), the diagnostic-evidence
# section requirement is ALSO checked. With no title, only the original
# mechanism-section check runs — preserving backward compatibility for callers
# that pre-date the evidence-section extension.
validate_pr_body() {
  local body="$1"
  # NL-FINDING-030: GitHub's API serves pull_request.body with CRLF line
  # endings, and the heading checks below use `grep -Fxq` (exact whole-line
  # match), so an otherwise-correct "## What mechanism..." line carrying a
  # trailing CR false-fails as "heading not found". Normalize CR out up front
  # so every downstream check sees LF-only lines. (MSYS grep masks \r locally,
  # which is why this only bites in Linux CI — verify with `od`, not grep.)
  body="${body//$'\r'/}"
  local title="${2:-${PR_TITLE:-}}"
  local body_chars=${#body}
  printf '[pr-template] checking PR body (%d chars)\n' "$body_chars"

  if ! find_section_heading "$body"; then
    emit_failure_message section_missing
    printf '[pr-template] verdict: FAIL\n'
    return 1
  fi
  printf '[pr-template] section heading found\n'

  local section_content
  section_content=$(extract_section_content "$body")
  local section_chars=${#section_content}
  printf '[pr-template] extracted %d chars of mechanism content\n' "$section_chars"

  # Try the strict "### a)/b)/c)" heading form first; fall back to the
  # AI-natural prose form ("(b) Label phrase. ...content...") that AI-
  # spawned PRs typically produce. Either is acceptable — the strict form
  # is for humans filling the template scaffold, the prose form is for
  # natural-paragraph answers. Both must select exactly one of a/b/c.
  local form form_source
  form=$(detect_answer_form "$section_content")
  form_source=heading
  if [[ "$form" == "NONE" ]]; then
    form=$(detect_ai_prose_form "$section_content")
    form_source=prose
  fi
  printf '[pr-template] answer form: %s (source: %s)\n' "$form" "$form_source"

  if [[ "$form" == "NONE" ]]; then
    emit_failure_message no_answer_form
    printf '[pr-template] verdict: FAIL\n'
    return 1
  fi

  # Placeholder check is scoped to the SELECTED sub-section when the
  # author used the strict heading form (residual placeholders under the
  # two unselected sub-headings are OK — they document the option set per
  # PULL_REQUEST_TEMPLATE.md line 11). When the author used the prose
  # form, there are no sub-section boundaries to scope to — placeholders
  # under untouched sub-headings would be a legitimate concern only if
  # the prose-form author ALSO left an unused scaffold in place. To match
  # the heading-form's contract, the prose-form check scopes to the
  # whole section EXCLUDING any text under sub-headings the prose author
  # did not select; in practice prose-form PRs omit the scaffold entirely
  # so the difference rarely matters.
  if [[ "$form_source" == "heading" ]]; then
    local selected_content
    selected_content=$(extract_selected_subsection "$section_content" "$form")
    if detect_placeholder "$selected_content"; then
      emit_failure_message placeholder_present
      printf '[pr-template] placeholder detection: PRESENT in selected sub-section (%s)\n' "$form"
      printf '[pr-template] verdict: FAIL\n'
      return 1
    fi
    printf '[pr-template] placeholder detection: ABSENT in selected sub-section (%s)\n' "$form"
  else
    # Prose form — scope placeholder check to the whole section minus any
    # text inside unselected ### sub-headings (so a prose author who left
    # the scaffold partially in place isn't double-penalized for residual
    # placeholders under the unselected scaffolds).
    local prose_check_content
    prose_check_content=$(printf '%s\n' "$section_content" | awk '
      BEGIN { skip = 0 }
      /^### / { skip = 1; next }
      { if (!skip) print }
    ')
    if detect_placeholder "$prose_check_content"; then
      emit_failure_message placeholder_present
      printf '[pr-template] placeholder detection: PRESENT in prose-form content (%s)\n' "$form"
      printf '[pr-template] verdict: FAIL\n'
      return 1
    fi
    printf '[pr-template] placeholder detection: ABSENT in prose-form content (%s)\n' "$form"
  fi

  if [[ "$form" == "c" ]]; then
    local rationale_chars
    if [[ "$form_source" == "heading" ]]; then
      rationale_chars=$(validate_rationale_length "$section_content")
    else
      rationale_chars=$(validate_rationale_length_prose "$section_content")
    fi
    printf '[pr-template] rationale length: %s chars (threshold: %d)\n' "$rationale_chars" "$PR_TEMPLATE_RATIONALE_MIN_CHARS"
    if [[ "$rationale_chars" -lt "$PR_TEMPLATE_RATIONALE_MIN_CHARS" ]]; then
      emit_failure_message rationale_short "$rationale_chars"
      printf '[pr-template] verdict: FAIL\n'
      return 1
    fi
  fi

  # Diagnostic-evidence check fires only if a title was supplied (either as
  # the 2nd positional arg or via the PR_TITLE env var). Without a title,
  # we cannot detect whether the PR claims to fix a recurring class.
  if [[ -n "$title" ]]; then
    if ! validate_evidence "$body" "$title"; then
      return 1
    fi
  else
    printf '[pr-template] evidence check: SKIP (no PR title supplied; pass PR_TITLE env or 2nd arg to enable)\n'
  fi

  printf '[pr-template] verdict: PASS\n'
  return 0
}

# --- Self-test ---------------------------------------------------------------
# When invoked directly with --self-test, run a battery of cases.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  echo "Running validator self-test..." >&2
  fails=0

  # Case 1: empty body → FAIL section_missing
  if validate_pr_body "" >/dev/null 2>&1; then
    echo "FAIL: empty body should have failed" >&2
    fails=$((fails + 1))
  fi

  # Case 2: body with heading but placeholder still present → FAIL
  case2=$(printf '## What mechanism would have caught this?\n\n### a) Existing catalog entry\n\n<mechanism answer — replace this bracketed text>\n')
  if validate_pr_body "$case2" >/dev/null 2>&1; then
    echo "FAIL: body with placeholder should have failed" >&2
    fails=$((fails + 1))
  fi

  # Case 3: body with (a) filled with substantive content → PASS
  case3=$(printf '## What mechanism would have caught this?\n\n### a) Existing catalog entry\n\nFM-006 self-reported task completion without evidence — caught by plan-edit-validator.\n')
  if ! validate_pr_body "$case3" >/dev/null 2>&1; then
    echo "FAIL: body with (a) filled should have passed" >&2
    fails=$((fails + 1))
  fi

  # Case 4: (c) with too-short rationale → FAIL rationale_short
  case4=$(printf '## What mechanism would have caught this?\n\n### c) No mechanism — accepted residual risk\n\nN/A\n')
  if validate_pr_body "$case4" >/dev/null 2>&1; then
    echo "FAIL: body with (c) too short should have failed" >&2
    fails=$((fails + 1))
  fi

  # Case 5: (c) with substantive rationale → PASS
  case5=$(printf '## What mechanism would have caught this?\n\n### c) No mechanism — accepted residual risk\n\nThis is a doc-only typo; no realistic mechanism would catch single-char prose typos without false positives.\n')
  if ! validate_pr_body "$case5" >/dev/null 2>&1; then
    echo "FAIL: body with (c) substantive rationale should have passed" >&2
    fails=$((fails + 1))
  fi

  # Case 6: heading present but no answer form selected → FAIL no_answer_form
  case6=$(printf '## What mechanism would have caught this?\n\n(some prose but no sub-heading)\n')
  if validate_pr_body "$case6" >/dev/null 2>&1; then
    echo "FAIL: body with no answer form should have failed" >&2
    fails=$((fails + 1))
  fi

  # Case 7: (c) filled with substantive content, (a) and (b) sub-headings
  # present with their bracketed placeholders intact → PASS.
  # Locks in the fix for the PR #14 scenario: the template explicitly
  # allows leaving placeholders under unselected sub-headings.
  case7=$(printf '## What mechanism would have caught this?\n\n### a) Existing catalog entry\n\n<mechanism answer — replace this bracketed text>\n\n### b) New catalog entry proposed\n\n<mechanism answer — replace this bracketed text>\n\n### c) No mechanism — accepted residual risk\n\nThis is a scoping-judgment correction; no realistic automated gate catches "an enumerated set broader than purpose" without unacceptable false positives.\n')
  if ! validate_pr_body "$case7" >/dev/null 2>&1; then
    echo "FAIL: (c) filled with placeholders under unselected (a)/(b) should have passed" >&2
    fails=$((fails + 1))
  fi

  # Case 8: (a) "selected" via substantive content BUT placeholder still
  # present under (a) sub-heading → FAIL placeholder_present. Negative
  # test ensuring we still catch un-deleted placeholders in the CHOSEN
  # sub-section (the case the original validator was guarding against).
  case8=$(printf '## What mechanism would have caught this?\n\n### a) Existing catalog entry\n\n<mechanism answer — replace this bracketed text>\nFM-006 self-reported task completion without evidence — caught by plan-edit-validator.\n')
  if validate_pr_body "$case8" >/dev/null 2>&1; then
    echo "FAIL: placeholder remaining in selected sub-section should have failed" >&2
    fails=$((fails + 1))
  fi

  # Case 9: (a) filled with substantive content, (b) and (c) sub-headings
  # present with placeholders → PASS. Mirror of case 7 with (a) selected.
  case9=$(printf '## What mechanism would have caught this?\n\n### a) Existing catalog entry\n\nFM-006 self-reported task completion without evidence — caught by plan-edit-validator.\n\n### b) New catalog entry proposed\n\n<mechanism answer — replace this bracketed text>\n\n### c) No mechanism — accepted residual risk\n\n<mechanism answer — replace this bracketed text>\n')
  if ! validate_pr_body "$case9" >/dev/null 2>&1; then
    echo "FAIL: (a) filled with placeholders under unselected (b)/(c) should have passed" >&2
    fails=$((fails + 1))
  fi

  # Case 10: AI-natural prose form with bold-marker (b) selection and
  # substantive content (no ### scaffolds at all) → PASS. This is the
  # dominant shape AI-spawned PRs produce; previously failed with
  # `answer form: NONE` despite substantive content.
  case10=$(printf '## What mechanism would have caught this?\n\n**(b) New catalog entry proposed.** This is a new failure-class candidate: FM-N orchestrator-surfacing-content has no emit path — when a writer hook only emits container events, the tree drifts stale.\n')
  if ! validate_pr_body "$case10" >/dev/null 2>&1; then
    echo "FAIL: prose-form (b) with substantive content should have passed" >&2
    fails=$((fails + 1))
  fi

  # Case 11: AI-natural prose form (c) without bold markup, substantive
  # rationale exceeding the 40-char threshold → PASS.
  case11=$(printf '## What mechanism would have caught this?\n\n(c) No mechanism — accepted residual risk. The original DEC-A choice was a deliberate spec, not a defect a gate could catch; the new responsive.selftest.js is itself the codified guard against regressing the contract going forward.\n')
  if ! validate_pr_body "$case11" >/dev/null 2>&1; then
    echo "FAIL: prose-form (c) with substantive rationale should have passed" >&2
    fails=$((fails + 1))
  fi

  # Case 12: AI-natural prose form (c) with too-short rationale → FAIL.
  # Locks in that the rationale-length check still applies to prose form.
  case12=$(printf '## What mechanism would have caught this?\n\n(c) None.\n')
  if validate_pr_body "$case12" >/dev/null 2>&1; then
    echo "FAIL: prose-form (c) with too-short rationale should have failed" >&2
    fails=$((fails + 1))
  fi

  # Case 13: AI-prose form-marker with NO substantive content beyond
  # the marker itself → FAIL no_answer_form (the prose detector requires
  # ≥30 chars of substantive content to register as a valid selection).
  case13=$(printf '## What mechanism would have caught this?\n\n(b)\n')
  if validate_pr_body "$case13" >/dev/null 2>&1; then
    echo "FAIL: prose-form (b) with no substantive content should have failed" >&2
    fails=$((fails + 1))
  fi

  # Case 14: heading form takes precedence over prose form when both are
  # present. Body has `### a)` filled AND a `(b)` prose line — heading
  # form wins, verdict is PASS based on (a). Confirms fallback ordering.
  case14=$(printf '## What mechanism would have caught this?\n\n### a) Existing catalog entry\n\nFM-006 self-reported task completion without evidence — caught by plan-edit-validator.\n\n### b) New catalog entry proposed\n\n<mechanism answer — replace this bracketed text>\n\n### c) No mechanism — accepted residual risk\n\n<mechanism answer — replace this bracketed text>\n\n(b) Also writing prose form which should not override the heading-form selection.\n')
  if ! validate_pr_body "$case14" >/dev/null 2>&1; then
    echo "FAIL: heading-form should take precedence when both forms present" >&2
    fails=$((fails + 1))
  fi

  # Case 15: prose-form author who happens to also paste in placeholder
  # text from the template (e.g., copy-paste of the bracketed text into
  # their prose) → FAIL placeholder_present. Catches the regression
  # where a prose-form PR ships with the placeholder string embedded.
  case15=$(printf '## What mechanism would have caught this?\n\n(b) New catalog entry proposed. <mechanism answer — replace this bracketed text> some other prose follows here too.\n')
  if validate_pr_body "$case15" >/dev/null 2>&1; then
    echo "FAIL: prose-form with placeholder text embedded should have failed" >&2
    fails=$((fails + 1))
  fi

  # --- Diagnostic-evidence cases (16-22) ------------------------------------
  # All cases below pass a substantive mechanism section + a PR title to
  # exercise the evidence-section logic added in the 2026-05-23 PR.

  mech_section=$'## What mechanism would have caught this?\n\n### a) Existing catalog entry\n\nFM-006 self-reported task completion without evidence.\n'

  # Case 16: non-fix-class title (no fix:/sweep/refactor in title) → evidence
  # check SKIPS regardless of section presence → PASS.
  case16="$mech_section"
  if ! validate_pr_body "$case16" "feat: add new dashboard widget" >/dev/null 2>&1; then
    echo "FAIL: non-fix-class title should skip evidence check" >&2
    fails=$((fails + 1))
  fi

  # Case 17: fix-class title + missing evidence section → FAIL evidence_section_missing.
  case17="$mech_section"
  if validate_pr_body "$case17" "fix: example bug in foo" >/dev/null 2>&1; then
    echo "FAIL: fix: title without evidence section should fail" >&2
    fails=$((fails + 1))
  fi

  # Case 18: sweep title with substantive [evidence-exempt: ...] marker → PASS.
  case18="$mech_section"$'\n[evidence-exempt: docs-only typo in a comment, no runtime behavior change]\n'
  if ! validate_pr_body "$case18" "sweep: rename helper across 12 files" >/dev/null 2>&1; then
    echo "FAIL: sweep with substantive evidence-exempt marker should pass" >&2
    fails=$((fails + 1))
  fi

  # Case 19: fix: title with too-short [evidence-exempt: ...] marker → FAIL evidence_exempt_too_short.
  case19="$mech_section"$'\n[evidence-exempt: tiny]\n'
  if validate_pr_body "$case19" "fix: example" >/dev/null 2>&1; then
    echo "FAIL: too-short evidence-exempt marker should fail" >&2
    fails=$((fails + 1))
  fi

  # Case 20: fix-class title + Primary evidence section with all four
  # sub-sections substantively filled → PASS.
  evidence_section=$'\n## Primary evidence (required for any sweep / class-fix / refactor PR)\n\n### What runtime/log evidence did you pull?\n\nvercel logs dpl_xyz --since 24h --limit 2000 --json, examined the failure window 14:00-15:00 UTC.\n\n### What did the evidence show?\n\n1760/2000 lines with "Unhandled Rejection: cannot use different slug names for the same dynamic path id !== orgId" — exact error string.\n\n### What hypothesis did you test BEFORE writing the fix?\n\nHYPOTHESIZED that renaming both segments to a consistent name removes the conflict — tested by inspecting the route tree under src/app/api/admin/orgs/[orgId]/ and confirming no other route uses [id] for the same parent.\n\n### What refutation criteria would have shown the hypothesis was wrong?\n\nWould be REFUTED by post-rename logs continuing to show the same Unhandled Rejection error in the next deployment.\n'
  case20="$mech_section$evidence_section"
  if ! validate_pr_body "$case20" "fix: route-tree slug conflict for org admin" >/dev/null 2>&1; then
    echo "FAIL: fix-class title with substantive evidence should pass" >&2
    fails=$((fails + 1))
  fi

  # Case 21: fix-class title + Primary evidence section with one sub-section
  # empty (placeholder remaining) → FAIL evidence_subsection_missing.
  evidence_section_thin=$'\n## Primary evidence (required for any sweep / class-fix / refactor PR)\n\n### What runtime/log evidence did you pull?\n\nvercel logs --since 24h covering the failure window.\n\n### What did the evidence show?\n\n<replace this bracketed text>\n\n### What hypothesis did you test BEFORE writing the fix?\n\nHYPOTHESIZED that renaming both segments removes the conflict.\n\n### What refutation criteria would have shown the hypothesis was wrong?\n\nWould be REFUTED by post-rename logs continuing to show the same error.\n'
  case21="$mech_section$evidence_section_thin"
  if validate_pr_body "$case21" "fix: example" >/dev/null 2>&1; then
    echo "FAIL: thin evidence sub-section should fail" >&2
    fails=$((fails + 1))
  fi

  # Case 22: PR_TITLE via env var rather than 2nd arg — same behavior as case 17.
  case22="$mech_section"
  if PR_TITLE="fix: same shape via env" validate_pr_body "$case22" >/dev/null 2>&1; then
    echo "FAIL: PR_TITLE env should trigger evidence check the same as 2nd arg" >&2
    fails=$((fails + 1))
  fi

  # Case 23 (NL-FINDING-030): a valid body with CRLF line endings — the shape
  # GitHub's API serves pull_request.body as — must PASS. Before the CR-strip
  # at the top of validate_pr_body, the trailing CR made grep -Fxq miss the
  # heading and this false-failed as section_missing.
  case23=$(printf '## What mechanism would have caught this?\r\n\r\n### a) Existing catalog entry\r\n\r\nFM-006 self-reported task completion without evidence — caught by plan-edit-validator.\r\n')
  if ! validate_pr_body "$case23" >/dev/null 2>&1; then
    echo "FAIL: CRLF-line-ending body (GitHub API shape) should have passed" >&2
    fails=$((fails + 1))
  fi

  total=23
  if [[ $fails -eq 0 ]]; then
    echo "Self-test passed ($total cases)" >&2
    exit 0
  else
    echo "Self-test failed: $fails case(s) failed (of $total)" >&2
    exit 1
  fi
fi
