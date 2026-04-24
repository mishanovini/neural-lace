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

# detect_placeholder <section_content>
# Returns 0 if the literal placeholder substring is found in the content,
# 1 otherwise.
#
# Note: extract_section_content already scopes to the mechanism section, so
# placeholder text under (b) or (c) sub-headings (which is expected when the
# author chose (a) and left the other sub-heading placeholders intact) IS
# caught by this check. The current convention is: the author replaces the
# placeholder text under their chosen sub-heading only. To pass, every
# `<mechanism answer ...>` placeholder in the whole mechanism section must
# be removed. This is intentional — leaving stale placeholders in the
# unselected sub-sections is sloppy, and removing them costs three deletes.
detect_placeholder() {
  local content="$1"
  # Use grep -F for literal (no regex) substring match.
  printf '%s\n' "$content" | grep -Fq "$PR_TEMPLATE_PLACEHOLDER"
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

# validate_pr_body <pr_body>
# Top-level validator. Returns 0 if the body passes all checks, 1 otherwise.
# Emits stdout progress logs and stderr canonical failure messages.
validate_pr_body() {
  local body="$1"
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

  if detect_placeholder "$section_content"; then
    emit_failure_message placeholder_present
    printf '[pr-template] placeholder detection: PRESENT\n'
    printf '[pr-template] verdict: FAIL\n'
    return 1
  fi
  printf '[pr-template] placeholder detection: ABSENT\n'

  local form
  form=$(detect_answer_form "$section_content")
  printf '[pr-template] answer form: %s\n' "$form"

  if [[ "$form" == "NONE" ]]; then
    emit_failure_message no_answer_form
    printf '[pr-template] verdict: FAIL\n'
    return 1
  fi

  if [[ "$form" == "c" ]]; then
    local rationale_chars
    rationale_chars=$(validate_rationale_length "$section_content")
    printf '[pr-template] rationale length: %s chars (threshold: %d)\n' "$rationale_chars" "$PR_TEMPLATE_RATIONALE_MIN_CHARS"
    if [[ "$rationale_chars" -lt "$PR_TEMPLATE_RATIONALE_MIN_CHARS" ]]; then
      emit_failure_message rationale_short "$rationale_chars"
      printf '[pr-template] verdict: FAIL\n'
      return 1
    fi
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

  if [[ $fails -eq 0 ]]; then
    echo "Self-test passed (6 cases)" >&2
    exit 0
  else
    echo "Self-test failed: $fails case(s) failed" >&2
    exit 1
  fi
fi
