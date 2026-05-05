#!/bin/bash
# harness-hygiene-sanitize.sh — propose replacements for hygiene-scan matches
#
# Reads scanner output from stdin OR a file argument, in the canonical scanner
# format: `[denylist] <file>:<line>: <content>` or `[heuristic] <file>:<line>: <content>`.
# (The leading `[denylist]` / `[heuristic]` tag is optional; rows without it are
# parsed as `<file>:<line>: <content>`.)
#
# For each match, classifies the offending text by pattern class and proposes
# a replacement. Emits a unified diff to stdout showing proposed changes.
# Does NOT modify any files; the user reviews and applies via `git apply`.
#
# Replacement classes:
#   - cloud-bucket           → <your-bucket>           (s3://, gs://, https://*.s3.*, *.r2.dev/)
#   - oauth-client-id        → <your-client-id>        (NNN...-...googleusercontent.com)
#   - project-internal-path  → src/<example-path>      (src/components/<Name>... etc.)
#   - capitalized-cluster    → <your-project>          (capitalized term repeated as project codename)
#   - customer-name          → <customer>              (heuristic — proper noun cluster on customer-class line)
#   - generic                → <redacted>              (fallback when no class matches)
#
# Usage:
#   harness-hygiene-scan.sh | harness-hygiene-sanitize.sh
#   harness-hygiene-sanitize.sh < scan-output.txt
#   harness-hygiene-sanitize.sh scan-output.txt
#   harness-hygiene-sanitize.sh --self-test

set -uo pipefail

SCRIPT_NAME="harness-hygiene-sanitize.sh"

# ---------------------------------------------------------------------------
# Classifier — given a content line, returns "<class>:<token-to-replace>"
# Returns empty string if no classifiable token found.
# ---------------------------------------------------------------------------

classify_match() {
  local content="$1"

  # 1. Cloud bucket — s3://bucket-name/... or gs://bucket-name/... or *.s3.*.amazonaws.com
  if [[ "$content" =~ (s3://[a-zA-Z0-9._-]+) ]]; then
    printf 'cloud-bucket:%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$content" =~ (gs://[a-zA-Z0-9._-]+) ]]; then
    printf 'cloud-bucket:%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$content" =~ (https://[a-zA-Z0-9.-]+\.s3\.[a-zA-Z0-9.-]+\.amazonaws\.com) ]]; then
    printf 'cloud-bucket:%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$content" =~ ([a-zA-Z0-9-]+\.r2\.dev) ]]; then
    printf 'cloud-bucket:%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  # 2. OAuth client-id — NNNNN...-XXX...apps.googleusercontent.com or just *.googleusercontent.com
  if [[ "$content" =~ ([0-9]{6,}-[a-zA-Z0-9_]+\.apps\.googleusercontent\.com) ]]; then
    printf 'oauth-client-id:%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$content" =~ ([0-9]{6,}-[a-zA-Z0-9_]+\.googleusercontent\.com) ]]; then
    printf 'oauth-client-id:%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  # 3. Project-internal path — src/components/<CamelCase>.tsx or src/app/.../<Name>.ts
  if [[ "$content" =~ (src/components/[A-Z][a-zA-Z0-9_]+\.tsx?) ]]; then
    printf 'project-internal-path:%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$content" =~ (src/app/[a-zA-Z0-9/_-]+/[A-Z][a-zA-Z0-9_]+\.tsx?) ]]; then
    printf 'project-internal-path:%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  # 4. Capitalized cluster — token like "Acme" or "Examplecorp" repeated as a codename
  # Match a CamelCase or capitalized term (>=4 chars, NOT a common English word).
  if [[ "$content" =~ ([A-Z][a-z]{3,}[A-Z]?[a-z]*) ]]; then
    local term="${BASH_REMATCH[1]}"
    # Skip common English words that happen to be capitalized (sentence start).
    case "$term" in
      The|This|That|These|Those|When|Where|Which|While|With|Without|From|Into|Over|Under|After|Before|During|Since|Until|Through|About|Above|Below|Across|Against|Around|Behind|Beyond|Inside|Outside|Toward|Within|Today|Tomorrow|Yesterday|Otherwise|Therefore|However|Moreover|Furthermore|Note|Also|Many|Some|Most|None|Each|Every|Other|Such|Very|Only|Even|Just|Both|Either|Neither|Then|Than|There|Here|Where|Will|Would|Could|Should|Must|Cannot|Does|Done|Have|Had|Make|Made|Take|Took|Find|Found|Used|Using|See|Set|Let|Get|Run|Read|Write|Show|Hide|Open|Close|Start|Stop|First|Last|Next|Prev|Previous|True|False|None|Empty|Full|None|Path|File|Line|Match|Text|Content|Data|Code|Type|Name|Form|Page|View|Menu|Item|List|Edit|Save|Send|Test|Demo|Example|Sample|Template)
        # fall through, no replacement proposed
        ;;
      *)
        printf 'capitalized-cluster:%s\n' "$term"
        return 0
        ;;
    esac
  fi

  # 5. No classification found
  return 1
}

propose_replacement() {
  local class="$1"
  case "$class" in
    cloud-bucket)            printf '<your-bucket>' ;;
    oauth-client-id)         printf '<your-client-id>' ;;
    project-internal-path)   printf 'src/<example-path>' ;;
    capitalized-cluster)     printf '<your-project>' ;;
    customer-name)           printf '<customer>' ;;
    *)                       printf '<redacted>' ;;
  esac
}

# ---------------------------------------------------------------------------
# Process input rows. For each row, classify, then build a per-file map of
# (line -> token-replacement-pair) to apply for diff generation.
# ---------------------------------------------------------------------------

process_input() {
  local input_source="$1"

  # Per-file accumulator: TMP_PROPOSALS holds <file>\t<line>\t<token>\t<replacement>
  local TMP_PROPOSALS
  TMP_PROPOSALS=$(mktemp)
  trap 'rm -f "$TMP_PROPOSALS"' RETURN

  local row file lineno content classified class token replacement
  while IFS= read -r row || [[ -n "$row" ]]; do
    [[ -z "$row" ]] && continue

    # Strip optional [tag] prefix
    row="${row#\[denylist\] }"
    row="${row#\[heuristic\] }"

    # Parse <file>:<line>: <content>
    if [[ "$row" =~ ^([^:]+):([0-9]+):[[:space:]]?(.*)$ ]]; then
      file="${BASH_REMATCH[1]}"
      lineno="${BASH_REMATCH[2]}"
      content="${BASH_REMATCH[3]}"
    else
      # Skip rows that do not match the expected format
      continue
    fi

    classified=$(classify_match "$content") || continue
    [[ -z "$classified" ]] && continue

    class="${classified%%:*}"
    token="${classified#*:}"
    replacement=$(propose_replacement "$class")

    printf '%s\t%s\t%s\t%s\n' "$file" "$lineno" "$token" "$replacement" >> "$TMP_PROPOSALS"
  done < "$input_source"

  if [[ ! -s "$TMP_PROPOSALS" ]]; then
    return 0
  fi

  # Group by file, build a sed-style replacement, generate diff per file.
  local files_seen
  files_seen=$(awk -F'\t' '{print $1}' "$TMP_PROPOSALS" | sort -u)

  local f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ ! -f "$f" ]]; then
      printf '# %s: file not found, skipping\n' "$f" >&2
      continue
    fi

    local TMP_NEW
    TMP_NEW=$(mktemp)

    # Apply all token→replacement substitutions for this file
    cp "$f" "$TMP_NEW"
    local row_token row_replacement
    while IFS=$'\t' read -r row_file row_line row_token row_replacement; do
      [[ "$row_file" != "$f" ]] && continue
      # Escape sed metacharacters in the search token and replacement
      local esc_token esc_repl
      esc_token=$(printf '%s' "$row_token" | sed -e 's/[\/&.[\*^$]/\\&/g')
      esc_repl=$(printf '%s' "$row_replacement" | sed -e 's/[\/&]/\\&/g')
      sed -i.bak "s/${esc_token}/${esc_repl}/g" "$TMP_NEW" 2>/dev/null
      rm -f "${TMP_NEW}.bak"
    done < "$TMP_PROPOSALS"

    # Emit unified diff
    diff -u "$f" "$TMP_NEW" 2>/dev/null | sed -e "1s|^--- .*|--- a/$f|" -e "2s|^+++ .*|+++ b/$f|"

    rm -f "$TMP_NEW"
  done <<< "$files_seen"
}

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

run_self_test() {
  local total=0 passed=0 failed=0
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "${TMPDIR_ST:-}"' EXIT

  cd "$TMPDIR_ST" || exit 1

  local SCRIPT_PATH
  SCRIPT_PATH="$OLDPWD_SCRIPT"

  # ----- Scenario s1: cloud-bucket match
  # NOTE: test fixture uses a neutral bucket name to avoid matching the harness denylist itself
  total=$((total+1))
  mkdir -p s1
  printf 'const url = "s3://example-bucket-xyz/assets/file.png";\n' > s1/config.ts
  printf '%s\n' '[denylist] s1/config.ts:1: const url = "s3://example-bucket-xyz/assets/file.png";' > s1/scan.txt
  s1_out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" s1/scan.txt 2>/dev/null)
  if printf '%s' "$s1_out" | grep -q '<your-bucket>' && printf '%s' "$s1_out" | grep -q -- '-.*s3://example-bucket-xyz'; then
    passed=$((passed+1))
    printf 's1 (cloud-bucket): PASS\n'
  else
    failed=$((failed+1))
    printf 's1 (cloud-bucket): FAIL\n'
    printf '   output:\n%s\n' "$s1_out"
  fi

  # ----- Scenario s2: OAuth client-id match
  total=$((total+1))
  mkdir -p s2
  printf 'CLIENT_ID="123456789012-abc123def456.apps.googleusercontent.com"\n' > s2/oauth.env
  printf '%s\n' '[denylist] s2/oauth.env:1: CLIENT_ID="123456789012-abc123def456.apps.googleusercontent.com"' > s2/scan.txt
  s2_out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" s2/scan.txt 2>/dev/null)
  if printf '%s' "$s2_out" | grep -q '<your-client-id>' && printf '%s' "$s2_out" | grep -q '123456789012-abc123def456'; then
    passed=$((passed+1))
    printf 's2 (oauth-client-id): PASS\n'
  else
    failed=$((failed+1))
    printf 's2 (oauth-client-id): FAIL\n'
    printf '   output:\n%s\n' "$s2_out"
  fi

  # ----- Scenario s3: project-internal path
  total=$((total+1))
  mkdir -p s3
  printf 'import { Foo } from "src/components/AcmeButton.tsx";\n' > s3/page.tsx
  printf '%s\n' '[heuristic] s3/page.tsx:1: import { Foo } from "src/components/AcmeButton.tsx";' > s3/scan.txt
  s3_out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" s3/scan.txt 2>/dev/null)
  if printf '%s' "$s3_out" | grep -q 'src/<example-path>' && printf '%s' "$s3_out" | grep -q 'AcmeButton'; then
    passed=$((passed+1))
    printf 's3 (project-internal-path): PASS\n'
  else
    failed=$((failed+1))
    printf 's3 (project-internal-path): FAIL\n'
    printf '   output:\n%s\n' "$s3_out"
  fi

  # ----- Scenario s4: capitalized cluster (codename)
  total=$((total+1))
  mkdir -p s4
  printf '%s\n' \
    '// Acme platform configuration' \
    'const acme = "Acme Inc.";' \
    'function loadAcme() { return acme; }' \
    'export const ACME_CONFIG = "Acme";' \
    '// Acme is a registered trademark.' > s4/branding.ts
  printf '%s\n' \
    '[heuristic] s4/branding.ts:1: // Acme platform configuration' \
    '[heuristic] s4/branding.ts:2: const acme = "Acme Inc.";' \
    '[heuristic] s4/branding.ts:4: export const ACME_CONFIG = "Acme";' > s4/scan.txt
  s4_out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" s4/scan.txt 2>/dev/null)
  if printf '%s' "$s4_out" | grep -q '<your-project>' && printf '%s' "$s4_out" | grep -q -- '-.*Acme'; then
    passed=$((passed+1))
    printf 's4 (capitalized-cluster): PASS\n'
  else
    failed=$((failed+1))
    printf 's4 (capitalized-cluster): FAIL\n'
    printf '   output:\n%s\n' "$s4_out"
  fi

  # ----- Scenario s5: clean input (no matches)
  total=$((total+1))
  mkdir -p s5
  printf 'just plain code\n' > s5/clean.ts
  printf '' > s5/scan.txt
  s5_out=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" s5/scan.txt 2>/dev/null)
  if [[ -z "$s5_out" ]]; then
    passed=$((passed+1))
    printf 's5 (clean-input): PASS\n'
  else
    failed=$((failed+1))
    printf 's5 (clean-input): FAIL\n'
    printf '   output:\n%s\n' "$s5_out"
  fi

  printf '\n%d/%d scenarios passed (%d failed)\n' "$passed" "$total" "$failed"
  if (( failed > 0 )); then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "--self-test" ]]; then
  # Resolve absolute path to the script before changing dirs in self-test
  OLDPWD_SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  export OLDPWD_SCRIPT
  run_self_test
  exit $?
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,28p' "$0"
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  if [[ ! -f "$1" ]]; then
    printf '%s: input file not found: %s\n' "$SCRIPT_NAME" "$1" >&2
    exit 2
  fi
  process_input "$1"
else
  # Read from stdin
  TMP_STDIN=$(mktemp)
  trap 'rm -f "$TMP_STDIN"' EXIT
  cat > "$TMP_STDIN"
  process_input "$TMP_STDIN"
fi

exit 0
