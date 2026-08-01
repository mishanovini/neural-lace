#!/bin/bash
# runtime-verification-executor.sh — Generation 4
#
# Parses "Runtime verification:" lines from an evidence file or section
# and EXECUTES each one. The hook verifies claims by running them, not
# by reading them.
#
# Accepted formats (one per line, prefix "Runtime verification: "):
#
#   test <test-file>::<test-name>
#     Requires the test file exists and defines a test with that name.
#     Does not run the test suite (too slow for a stop hook); just
#     verifies the named test is defined. This catches "I wrote a test"
#     claims that don't match any real test.
#
#   curl <full curl command including URL and flags>
#     NOT EXECUTED by default — classified UNVERIFIABLE. See "THE GOVERNING
#     BOUNDARY" below. Pass --allow-exec on a manual/interactive run to
#     actually replay it.
#     Example:
#       Runtime verification: curl -s http://localhost:3000/api/foo
#
#   sql <SELECT statement>
#     NOT EXECUTED by default — classified UNVERIFIABLE, same as curl.
#     Under --allow-exec, runs the statement against $SUPABASE_TEST_DB_URL
#     via psql.
#     Example:
#       Runtime verification: sql SELECT count(*) FROM messages WHERE metadata IS NOT NULL
#
#   playwright <spec-file>::<test-name>
#     Verifies the spec file exists and defines a test with that name.
#     Does not run Playwright (slow); just asserts the test exists.
#
#   file <path>::<line-pattern>
#     Verifies the file exists and contains a line matching the pattern.
#     Used for "this code change is present at file:line" checks.
#
# ANY OTHER FORMAT IS REJECTED as unparseable — including bare text like
# "manual test done" or "verified in browser". That is the whole point.
#
# ==========================================================================
# THE GOVERNING BOUNDARY (2026-07-31 security fix — read before adding a
# branch that spawns a process)
# ==========================================================================
#
#   VERIFY BY READING FILES, NEVER BY RUNNING CONTENT.
#
# This executor's input is a markdown file. Markdown files in this repo are
# attacker-controllable in at least three PROVEN ways: (i) an untracked .md
# is read whole-file by the gate, so a postmortem or review that merely
# QUOTES an evidence line supplies one; (ii) a CLEAN working tree with
# someone else's branch checked out supplies THEIR committed lines through
# the base..HEAD diff; (iii) an agent writes its own evidence. Anything this
# file executes, those three paths execute — at every session end, with no
# human in the loop.
#
# The `curl` and `sql` branches used to execute. That was a live remote-code-
# execution vector, demonstrated end-to-end: an evidence file whose only line
# was `Runtime verification: curl -o <path> file:///etc/hosts` exited 0 and
# CREATED the file (213 bytes of /etc/hosts); a second run OVERWROTE an
# executable hook script, i.e. next-session code execution. The metacharacter
# regex in the curl branch was the only filter and it does not filter curl
# FLAGS, so `-o` (arbitrary write), `-T` (upload/exfiltrate any readable
# file) and `-K` (arbitrary curl config) all passed it. `sql` was the same
# shape one layer over: psql reads its stdin as if typed, and `\!` there is
# a shell escape.
#
# Both are now classified UNVERIFIABLE by default — exactly as `command` and
# `bash` already were, which is what the carrier gate's header always claimed
# this executor did. Execution survives ONLY behind the explicit
# --allow-exec flag, which no automated caller passes -- in fact there is
# currently NO live invoker of this file at all (pre-stop-verifier.sh is an
# exit-0 shim, ADR 058 D5; the intended carrier from 2b6e6a5 never landed),
# so the flag can only arrive from an operator-typed command line. Under --allow-exec the line runs AS WRITTEN, with only the
# metacharacter filter and no flag denylist: a flag denylist would be
# incomplete by construction and would buy false confidence, so the honest
# contract is "--allow-exec is for evidence you trust, on a run you started".
#
# The remaining branches (`file`, `test`, `playwright`) READ the cited file
# with grep and spawn nothing that carries evidence content as code. Any new
# branch must stay on that side of the line.
#
# Usage:
#   bash runtime-verification-executor.sh [--allow-exec] <evidence-file>
#   OR
#   cat evidence.md | bash runtime-verification-executor.sh [--allow-exec] -
#
# Exit codes:
#   0 — every Runtime verification: line parsed AND executed successfully
#   1 — one or more lines failed (stderr lists each)
#   2 — input error (file missing, empty, etc.)

set -u

# --- portable bounded subprocess (plan macos-portability-2026-07, M3) -----
# `timeout` is GNU coreutils and is ABSENT on stock macOS. This file used to
# call it bare, so on a Mac the curl branch below got rc=127 and reported
# "curl exit 127" — blaming the operator's evidence for a missing tool and
# failing every curl evidence line on the machine. nl_run_bounded prefers
# real GNU `timeout` (unchanged behavior on Windows/Git-bash and on a
# coreutils Mac) and otherwise bounds the command itself.
# Sourced defensively: on a partial install the shim keeps the hook working
# and SAYS SO rather than dropping the bound silently.
{ source "$(dirname "${BASH_SOURCE[0]}")/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local s="${1:-0}"; shift 2>/dev/null || true
    echo "runtime-verification-executor: WARN hooks/lib/portable-timeout.sh missing — running UNBOUNDED (wanted ${s}s): ${1:-<none>}" >&2
    [ "$#" -gt 0 ] || return 2
    "$@"
  }
fi

# --- evidence-convention parsing (2026-07-31 resurrection) ----------------
# The formats above were written for a JS/TS product repo. The repo's ACTUAL
# evidence convention drifted underneath them while the gate was dead (its
# only caller, pre-stop-verifier.sh, became an exit-0 shim at ADR 058 D5), so
# nothing ever re-measured the parser against the corpus it parses. Measured
# at 3caaeff over the 1344 non-curl `Runtime verification:` lines in
# docs/plans/*evidence*.md, the pre-fix parser scored 986 FAIL / 358 PASS --
# a ~73% false-positive rate against evidence that is in the main TRUE. Three
# concrete parser defects produced almost all of it:
#
#   1. Trailing annotation. Evidence today is written
#        file <path>::<pattern> (<the command run> -> <its output>)
#      and the parser took everything after `::` as the grep pattern,
#      annotation included, so no pattern ever matched. _rve_strip_annotation
#      removes one balanced trailing " (...)" group.
#   2. `grep -qE "$pattern"` with a pattern starting `-` (the repo's dominant
#      cited symbol is literally `--self-test`) made grep parse the pattern as
#      OPTIONS and error out. Fixed with a `--` end-of-options guard.
#   3. Shell self-tests. `test <file>::<name>` only ever looked for the JS
#      idiom `test('name'` / `it('name'`. This repo's test idiom is a shell
#      script's `--self-test` mode, which that regex can never match.
#
# UNVERIFIABLE is a THIRD outcome, deliberately distinct from PASS and FAIL.
# Lines the executor cannot soundly check -- unknown formats (`command`,
# `bash`, `functionality-verifier`), `curl`/`sql` lines absent --allow-exec
# (see THE GOVERNING BOUNDARY above), and placeholder paths (`<repo>/...`,
# `<home>/...`) that name no real file -- are counted and reported but do NOT
# fail the run. Passing them silently would be the vacuous-gate failure mode;
# failing them would make the gate a cry-wolf on legitimate evidence it was
# never designed to execute. They are a real bypass and are enumerated as one
# in this unit's manifest bypass_paths rather than papered over here.

_rve_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD"
}

# _rve_strip_annotation <string> — removes ONE balanced trailing " (...)"
# group, so `--self-test (bash x.sh --self-test -> 16 passed)` yields
# `--self-test`. Scans right-to-left tracking depth so nested parens inside
# the annotation do not truncate it early. A string not ending in ")" and a
# group not preceded by a space are both returned unchanged (a pattern may
# legitimately end in a paren).
_rve_strip_annotation() {
  local s="$1" i depth ch
  case "$s" in *")") ;; *) printf '%s' "$s"; return 0 ;; esac
  depth=0
  i=$(( ${#s} - 1 ))
  while [[ $i -ge 0 ]]; do
    ch="${s:$i:1}"
    if [[ "$ch" == ")" ]]; then
      depth=$(( depth + 1 ))
    elif [[ "$ch" == "(" ]]; then
      depth=$(( depth - 1 ))
      if [[ $depth -eq 0 ]]; then
        if [[ $i -gt 0 && "${s:$((i-1)):1}" == " " ]]; then
          printf '%s' "${s:0:$((i-1))}"
        else
          printf '%s' "$s"
        fi
        return 0
      fi
    fi
    i=$(( i - 1 ))
  done
  printf '%s' "$s"
}

# _rve_resolve_path <path> — prints an on-disk path to check, or EMPTY when
# the citation is a placeholder the executor cannot resolve to a real file.
# `~/...` IS expanded: those cite the live ~/.claude mirror, which is a real
# checkable location. `<repo>/...`, `<home>/...`, `$VAR/...` are placeholders.
_rve_resolve_path() {
  local p="$1"
  case "$p" in
    "<"*|'$'*|"") printf ''; return 0 ;;
    "~/"*)        printf '%s/%s' "${HOME}" "${p#\~/}"; return 0 ;;
    "~")          printf '%s' "${HOME}"; return 0 ;;
    /*)           printf '%s' "$p"; return 0 ;;
    *)            printf '%s/%s' "$(_rve_repo_root)" "$p"; return 0 ;;
  esac
}

# _rve_cites_shell_mode <file> — true when the cited test target is a shell
# script (or any non-JS/TS file). Those are verified by literal presence of
# the cited mode string (e.g. `--self-test`), not by the JS `test('name'`
# regex, which cannot match a shell script by construction.
_rve_cites_shell_mode() {
  case "$1" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) return 1 ;;
    *) return 0 ;;
  esac
}

# --------------------------------------------------------------------------
# --self-test — parser-level. Each scenario writes a real fixture file and
# invokes THIS script as a subprocess against it, so what is asserted is the
# executed CLI contract (exit code + stderr), never a regex over this file's
# own source. Scenarios 1/2 are the RED/GREEN twin pair for the golden
# scenario (a fabricated `file` citation); 3-5 are regressions pinning the
# three parser defects that made the pre-fix executor 73% false-positive.
# --------------------------------------------------------------------------
_rve_self_test() {
  local self pass=0 fail=0 tmp
  # Absolute: scenarios cd into the fixture dir, so a relative $0 would 127.
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  tmp=$(mktemp -d 2>/dev/null) || { echo "self-test: cannot create tempdir" >&2; return 2; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  cat > "$tmp/subject.sh" <<'FIX'
#!/bin/bash
# a fixture script that really does declare a --self-test mode
if [[ "${1:-}" == "--self-test" ]]; then echo "ok"; fi
FIX
  cat > "$tmp/subject.test.ts" <<'FIX'
import { thing } from './thing';
test('renders the badge', () => { expect(thing()).toBe(1); });
FIX

  # _case <label> <expected-rc> <evidence-line...>  (evidence via stdin file)
  #
  # The subject is invoked as "${BASH:-bash}", NOT bare `bash`. Bare `bash`
  # resolves through PATH, where /opt/homebrew/bin/bash (5.x) precedes
  # /bin/bash (3.2.57) on this machine — so a suite run BY 3.2 to prove
  # bash-3.2 compatibility silently re-entered the subject under 5.x and the
  # 3.2 column exercised only this outer harness. $BASH is the interpreter
  # actually running this file, so the column now means what it claims.
  _ST_FLAGS=""
  _ST_OUT=""
  _c() {
    local label="$1" want="$2"; shift 2
    printf '%s\n' "$@" > "$tmp/ev.md"
    local out rc
    # shellcheck disable=SC2086  # word-splitting $_ST_FLAGS is intended
    out=$(cd "$tmp" && "${BASH:-bash}" "$self" ${_ST_FLAGS} "$tmp/ev.md" 2>&1); rc=$?
    _ST_OUT="$out"
    if [[ "$rc" -eq "$want" ]]; then
      pass=$((pass + 1)); echo "self-test ($label): PASS (exit $rc)" >&2
    else
      fail=$((fail + 1)); echo "self-test ($label): FAIL (expected exit $want, got $rc) :: $out" >&2
    fi
  }

  # _expect_out <label> <substring> — asserts the last _c run's combined
  # output contains <substring>. Exit code alone cannot distinguish
  # "classified UNVERIFIABLE" from "executed and passed": both are exit 0.
  _expect_out() {
    local label="$1" want="$2"
    case "$_ST_OUT" in
      *"$want"*) pass=$((pass + 1)); echo "self-test ($label): PASS" >&2 ;;
      *) fail=$((fail + 1)); echo "self-test ($label): FAIL (output lacks '$want') :: $_ST_OUT" >&2 ;;
    esac
  }

  # _expect_absent <label> <path> — asserts a file was NOT created. This is
  # the side-effect assertion the exit code cannot make.
  _expect_absent() {
    local label="$1" p="$2"
    if [[ -e "$p" ]]; then
      fail=$((fail + 1)); echo "self-test ($label): FAIL — $p EXISTS ($(wc -c < "$p" | tr -d ' ') bytes); the executor wrote a file it was told never to write" >&2
    else
      pass=$((pass + 1)); echo "self-test ($label): PASS (no file written)" >&2
    fi
  }

  # 1. RED — the golden scenario: a `file` citation whose pattern is NOT in
  #    the cited file (fabricated evidence). MUST fail.
  _c "red-fabricated-file-citation" 1 \
    "Runtime verification: file $tmp/subject.sh::THIS_STRING_IS_NOT_IN_THE_FILE"
  # 2. GREEN twin — same shape, pattern genuinely present. MUST stay silent.
  _c "green-truthful-file-citation" 0 \
    "Runtime verification: file $tmp/subject.sh::a fixture script that really does"
  # 3. Regression: trailing " (annotation)" must be stripped, not grepped.
  _c "green-annotation-stripped" 0 \
    "Runtime verification: file $tmp/subject.sh::declare a --self-test mode (bash subject.sh --self-test -> ok)"
  # 4. Regression: a pattern starting with '-' must not be parsed by grep as
  #    options (pre-fix this errored and reported a false FAIL).
  _c "green-leading-dash-pattern" 0 \
    "Runtime verification: file $tmp/subject.sh::--self-test"
  # 5. Regression: the shell `--self-test` idiom under the `test` format.
  _c "green-shell-selftest-idiom" 0 \
    "Runtime verification: test $tmp/subject.sh::--self-test"
  # 5b. and its RED twin — a mode the script does NOT declare.
  _c "red-shell-mode-not-declared" 1 \
    "Runtime verification: test $tmp/subject.sh::--dry-run"
  # 6. Backward compat: the original JS/TS test idiom still verifies.
  _c "green-js-test-idiom" 0 \
    "Runtime verification: test $tmp/subject.test.ts::renders the badge"
  # 7. A cited file that does not exist is a FAIL, not a pass.
  _c "red-cited-file-missing" 1 \
    "Runtime verification: file $tmp/nope.sh::some concrete content here"
  # 8. UNVERIFIABLE: unknown format is reported, not failed and not passed.
  _c "unverifiable-unknown-format" 0 \
    "Runtime verification: command bash scripts/whatever.sh"
  # 9. UNVERIFIABLE: placeholder path resolves to no real file.
  _c "unverifiable-placeholder-path" 0 \
    "Runtime verification: file <repo>/adapters/x.sh::some concrete content"
  # 10. A trivially-matching pattern is still rejected as INVALID.
  _c "red-trivial-pattern-rejected" 1 \
    "Runtime verification: file $tmp/subject.sh::.*"
  # 11. Repo-relative resolution: cwd is the fixture dir (no git repo), so
  #     _rve_repo_root falls back to $PWD and `subject.sh` resolves.
  _c "green-relative-path-resolves" 0 \
    "Runtime verification: file subject.sh::a fixture script that really does"
  # 12. UNVERIFIABLE lines must not mask a real FAIL in the same file.
  _c "red-fail-not-masked-by-unverifiable" 1 \
    "Runtime verification: command bash scripts/whatever.sh" \
    "Runtime verification: file $tmp/subject.sh::THIS_STRING_IS_NOT_IN_THE_FILE"

  # ---- THE GOVERNING BOUNDARY: verify by reading, never by running --------

  # 13. THE ATTACK, verbatim. An evidence file whose only line is a `curl -o`
  #     write primitive. Before the fix this exited 0 AND CREATED THE FILE
  #     (213 bytes of /etc/hosts); pointed at a hook script it overwrote it,
  #     i.e. next-session code execution. Three assertions, because exit 0 is
  #     the SAME code the vulnerable version returned: the classification
  #     must be UNVERIFIABLE, and the file must not exist.
  _c "curl-write-primitive-not-executed" 0 \
    "Runtime verification: curl -o $tmp/PWNED.txt file:///etc/hosts"
  _expect_out "curl-write-primitive-classified-unverifiable" "UNVERIFIABLE"
  _expect_absent "curl-write-primitive-wrote-nothing" "$tmp/PWNED.txt"

  # 14. The read/exfiltrate half of the same primitive: `curl -T` uploads any
  #     readable file. Same three assertions.
  printf 'SECRET-CANARY\n' > "$tmp/secret.txt"
  _c "curl-upload-primitive-not-executed" 0 \
    "Runtime verification: curl -T $tmp/secret.txt file://$tmp/EXFIL.txt"
  _expect_out "curl-upload-primitive-classified-unverifiable" "UNVERIFIABLE"
  _expect_absent "curl-upload-primitive-copied-nothing" "$tmp/EXFIL.txt"

  # 15. `sql` is the same class (psql runs its stdin as if typed; `\!` is a
  #     shell escape) and must be classified identically, NOT failed.
  _c "sql-not-executed" 0 \
    "Runtime verification: sql SELECT count(*) FROM messages"
  _expect_out "sql-classified-unverifiable" "UNVERIFIABLE"

  # 16. ...and an unreachable curl must not be a FAIL either. This is the
  #     end-to-end false-positive that made the gate cry wolf on the repo's
  #     own convention: a TRUE evidence line whose server is simply not
  #     running at session end. UNVERIFIABLE, exit 0.
  _c "curl-unreachable-is-not-a-failure" 0 \
    "Runtime verification: curl -s http://127.0.0.1:7733/api/health"
  _expect_out "curl-unreachable-classified-unverifiable" "UNVERIFIABLE"

  # ---- the opt-in is REAL (a flag nobody can honor is theatre) ------------

  # 17. Under --allow-exec the curl branch executes again. Proven without a
  #     network: a file:// URL is a real curl execution whose success is
  #     observable, and its RED twin below is a URL curl cannot resolve.
  #     The "1 verification(s) passed" assertion is load-bearing: exit 0 is
  #     ALSO what a not-executed UNVERIFIABLE line returns, so the exit code
  #     alone cannot tell a working opt-in from a dead one.
  _ST_FLAGS="--allow-exec"
  _c "allow-exec-runs-curl" 0 \
    "Runtime verification: curl -s file://$tmp/subject.sh"
  _expect_out "allow-exec-curl-actually-executed" "1 verification(s) passed"
  # 18. ...and still reports a genuine failure under the flag.
  _c "allow-exec-curl-failure-still-fails" 1 \
    "Runtime verification: curl -s file://$tmp/definitely-not-here.txt"

  # 19. CRITICAL-3 REGRESSION at the shared parse point. The repo's own
  #     convention appends a " (annotation)" to the command. Because the
  #     strip now happens BEFORE the format case, the curl branch sees an
  #     annotation-free body; previously the parens reached the
  #     metacharacter filter and the line was rejected INVALID — 14 of 23
  #     real curl lines in docs/ failed for exactly this, on TRUE evidence.
  _c "annotation-stripped-before-curl-branch" 0 \
    "Runtime verification: curl -s file://$tmp/subject.sh (returns the fixture, HTTP 200)"
  _expect_out "annotation-stripped-line-actually-passed" "1 verification(s) passed"
  _ST_FLAGS=""

  # 20. The flag is a FLAG, not an env var: an inherited environment must
  #     never re-arm execution. (An env opt-in in a settings.json `env`
  #     block would silently restore the session-end RCE.)
  rm -f "$tmp/ENVPWNED.txt"
  local envout envrc
  printf 'Runtime verification: curl -o %s file:///etc/hosts\n' "$tmp/ENVPWNED.txt" > "$tmp/env-ev.md"
  envout=$(cd "$tmp" && _RVE_ALLOW_EXEC=1 RVE_ALLOW_EXEC=1 NL_RVE_ALLOW_EXEC=1 \
    "${BASH:-bash}" "$self" "$tmp/env-ev.md" 2>&1); envrc=$?
  if [[ "$envrc" -eq 0 && ! -e "$tmp/ENVPWNED.txt" ]]; then
    pass=$((pass + 1)); echo "self-test (env-cannot-re-arm-execution): PASS" >&2
  else
    fail=$((fail + 1)); echo "self-test (env-cannot-re-arm-execution): FAIL (rc=$envrc, file exists: $([[ -e "$tmp/ENVPWNED.txt" ]] && echo yes || echo no)) :: $envout" >&2
  fi

  echo "self-test summary: ${pass} passed, ${fail} failed" >&2
  [[ "$fail" -eq 0 ]]
}

# --------------------------------------------------------------------------
# Argument parsing.
#
# _RVE_ALLOW_EXEC is the opt-in that re-enables the two branches that spawn a
# process carrying evidence content (`curl`, `sql`). It is a FLAG and only a
# flag: deliberately NOT an environment variable, because an env var can be
# set once in a settings.json `env` block and silently re-arm execution on
# every future Stop — which is the exact property that made the original bug
# a session-end RCE rather than a bounded one. A caller must type it.
# --------------------------------------------------------------------------
_RVE_ALLOW_EXEC=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      _rve_self_test
      exit $?
      ;;
    --allow-exec)
      _RVE_ALLOW_EXEC=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 [--allow-exec] <evidence-file|-> | --self-test" >&2
  exit 2
fi

INPUT_SRC="$1"

if [[ "$INPUT_SRC" == "-" ]]; then
  EVIDENCE=$(cat)
else
  if [[ ! -f "$INPUT_SRC" ]]; then
    echo "runtime-verification-executor: input file not found: $INPUT_SRC" >&2
    exit 2
  fi
  EVIDENCE=$(cat "$INPUT_SRC")
fi

if [[ -z "$EVIDENCE" ]]; then
  # Empty input — nothing to verify. Treat as success (the caller should
  # have its own "evidence exists" check).
  exit 0
fi

# Extract Runtime verification: lines
LINES=$(echo "$EVIDENCE" | grep -E '^Runtime verification:' || true)

if [[ -z "$LINES" ]]; then
  # No runtime-verification entries at all. The caller decides whether
  # that's acceptable (pre-stop-verifier blocks in some cases).
  exit 0
fi

PASS_COUNT=0
FAIL_COUNT=0
UNVERIF_COUNT=0
FAILURES=""
UNVERIFIABLE=""

while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  # Strip the "Runtime verification: " prefix
  body="${line#Runtime verification:}"
  body="${body# }"  # trim leading space

  # First token is the format type
  fmt=$(echo "$body" | awk '{print $1}')
  rest=$(echo "$body" | cut -d' ' -f2-)

  # Trailing " (annotation)" is stripped ONCE, HERE, at the shared parse
  # point — before the format case — so EVERY branch sees an annotation-free
  # body. It used to be stripped inside the `test|playwright` and `file`
  # branches only, which meant the repo's own dominant evidence convention
  #   curl http://127.0.0.1:7733/api/health (returns ok=true)
  # reached the curl branch with the parens still attached and was rejected
  # INVALID by the metacharacter filter — 14 of 23 real curl lines in docs/
  # failed for that reason alone, on evidence that was TRUE. A per-branch fix
  # would have left the next branch to rediscover the same bug; the parse
  # point is where the annotation stops being part of the body.
  rest=$(_rve_strip_annotation "$rest")

  case "$fmt" in
    test|playwright)
      # Format: test <file>::<name>  OR  playwright <spec>::<name>
      #
      # Verifies the cited test (a) exists in the file, (b) is not itself
      # a skipped test, and (c) the file does not contain runtime
      # conditional skips that could silently no-op the entire suite.
      #
      # Check (c) was added to catch "vaporware tests" — tests that
      # appear to run but are runtime-skipped by conditions like
      # `test.skip(!ENV_VAR, '...')` at the top of a describe block
      # that evaluates false whenever the env var is unset. Rather than
      # re-running every test at session end (too slow), the executor
      # statically rejects any file where a named test or the enclosing
      # describe is skippable without positive proof that the skip is
      # deliberate.
      #
      # Escape hatch: annotate the skip line with
      #   // harness-allow-skip: <short reason>
      # and the check will pass. Use this for genuinely optional tests
      # (e.g. tests that require a feature flag), not for "the credential
      # isn't set yet" skips — those ARE the failure mode this guards.
      if [[ "$rest" != *"::"* ]]; then
        FAILURES+="  INVALID: '$line' — expected '$fmt <file>::<name>'"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      test_file="${rest%%::*}"
      test_name="${rest#*::}"   # already annotation-stripped at the parse point
      test_path=$(_rve_resolve_path "$test_file")
      if [[ -z "$test_path" ]]; then
        UNVERIFIABLE+="  UNVERIFIABLE: '$line' — '$test_file' is a placeholder path, not a real file the executor can open"$'\n'
        UNVERIF_COUNT=$((UNVERIF_COUNT + 1))
        continue
      fi
      if [[ ! -f "$test_path" ]]; then
        FAILURES+="  FAIL: '$line' — $fmt file not found: $test_path"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      if _rve_cites_shell_mode "$test_path"; then
        # Shell/other: this repo's test idiom is a script's own `--self-test`
        # mode, which the JS `test('name'` regex below can never match. Verify
        # the cited mode string is literally declared by the script.
        if ! grep -qF -- "$test_name" "$test_path" 2>/dev/null; then
          FAILURES+="  FAIL: '$line' — $test_path does not declare '$test_name' (cited $fmt mode not found in the script)"$'\n'
          FAIL_COUNT=$((FAIL_COUNT + 1))
          continue
        fi
        PASS_COUNT=$((PASS_COUNT + 1))
        continue
      fi
      # Must grep for test('<name>' OR it('<name>' (unquoted styles too)
      if ! grep -qE -- "(test|it)[[:space:]]*\([[:space:]]*['\"]${test_name}['\"]" "$test_path" 2>/dev/null; then
        FAILURES+="  FAIL: '$line' — no test named '$test_name' in $test_path"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      test_file="$test_path"
      # Check (b): the cited test itself is written as .skip(...)
      if grep -qE "(test|it)\.skip\s*\(\s*['\"]${test_name}['\"]" "$test_file" 2>/dev/null; then
        FAILURES+="  FAIL: '$line' — cited test is written as .skip() in $test_file. A skipped test cannot serve as runtime verification. Remove the .skip or pick a different test."$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Check (c): the file contains a runtime conditional skip that can
      # no-op the whole suite (e.g. test.skip(!ENV_VAR, 'reason') or
      # test.skip(process.env.X == null, ...)). Allowed only if the line
      # carries a `// harness-allow-skip:` annotation.
      conditional_skips=$(grep -nE "(test|describe|it)\.skip\s*\(\s*(!|process\.env|typeof\s+process)" "$test_file" 2>/dev/null || true)
      if [[ -n "$conditional_skips" ]]; then
        # Check each flagged line for an allow annotation on the same line
        unannotated=""
        while IFS= read -r flagged; do
          [[ -z "$flagged" ]] && continue
          if echo "$flagged" | grep -q "harness-allow-skip:"; then
            continue
          fi
          unannotated+="      $flagged"$'\n'
        done <<< "$conditional_skips"
        if [[ -n "$unannotated" ]]; then
          FAILURES+="  FAIL: '$line' — $test_file contains unannotated runtime conditional skips that can silently no-op the suite. Either remove the skip or add '// harness-allow-skip: <reason>' on the same line."$'\n'
          FAILURES+="$unannotated"
          FAIL_COUNT=$((FAIL_COUNT + 1))
          continue
        fi
      fi
      PASS_COUNT=$((PASS_COUNT + 1))
      ;;

    curl)
      # Format: curl <full command>
      #
      # DEFAULT: NOT EXECUTED. See THE GOVERNING BOUNDARY in the header.
      # Replaying a curl command harvested from a markdown file spawns a
      # process whose ARGV is attacker-controlled, and curl's own flags are a
      # complete write (`-o`), read/exfiltrate (`-T`) and config-injection
      # (`-K`) primitive. Both `-o` and `-T` were demonstrated end-to-end
      # against this branch. It is classified UNVERIFIABLE for the same
      # reason `command` and `bash` always were, and this is checked BEFORE
      # any parsing of $rest so no code path can reach curl by accident.
      if [[ "$_RVE_ALLOW_EXEC" -ne 1 ]]; then
        UNVERIFIABLE+="  UNVERIFIABLE: '$line' — 'curl' evidence is not executed (running content harvested from a markdown file is a code-execution vector; verify by READING files instead). Re-run this executor manually with --allow-exec to replay it, or cite the change with a 'file <path>::<pattern>' line the gate can check by reading."$'\n'
        UNVERIF_COUNT=$((UNVERIF_COUNT + 1))
        continue
      fi
      # --- from here on: the operator explicitly opted in with --allow-exec.
      # We run it with a short timeout and check exit code + response.
      #
      # SECURITY: previously this used `bash -c "curl ... $rest"` which
      # shell-interpolated the user-supplied tail. Evidence like
      # `curl http://x.com; rm -rf ~` would execute the `rm`. That was a
      # pre-stop-verifier code-execution bug. The fix: parse $rest as an
      # argv array, reject any entry containing shell metacharacters, and
      # exec curl directly (no shell). NOTE this filter does NOT restrict
      # curl's own flags — see the header for why a flag denylist is not
      # attempted here.
      if [[ -z "$rest" ]]; then
        FAILURES+="  INVALID: '$line' — empty curl command"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Reject shell metacharacters that would allow command injection
      # if any future change re-introduces `bash -c`. Also rejects them
      # now to ensure the evidence is a pure curl invocation, nothing else.
      if echo "$rest" | grep -qE '[;&|`$(){}<>]|\$\(|&&|\|\|'; then
        FAILURES+="  INVALID: '$line' — curl command contains shell metacharacters (; & | \` \$ () {} <> && || \$()); evidence must be a pure curl invocation"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Split $rest on whitespace into argv (word-splitting is desired here
      # precisely because we rejected shell metacharacters above).
      # shellcheck disable=SC2206
      curl_args=($rest)
      # Force our safe flags in front regardless of what the builder wrote.
      # The outer bound is belt-and-braces over curl's own --max-time 8; it
      # exists to catch a curl that wedges before its own timer arms.
      response=$(nl_run_bounded 10 curl -s --max-time 8 --connect-timeout 3 "${curl_args[@]}" 2>&1)
      curl_exit=$?
      if [[ $curl_exit -eq 124 ]]; then
        FAILURES+="  FAIL: '$line' — curl exceeded the 10s bound (killed): $(echo "$response" | head -c 200)"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      if [[ $curl_exit -ne 0 ]]; then
        FAILURES+="  FAIL: '$line' — curl exit $curl_exit: $(echo "$response" | head -c 200)"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Detect a top-level JSON error field as a failure signal
      if echo "$response" | grep -qE '^\{"error":' || echo "$response" | grep -qE '"status":\s*"error"'; then
        FAILURES+="  FAIL: '$line' — response contains error: $(echo "$response" | head -c 200)"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      PASS_COUNT=$((PASS_COUNT + 1))
      ;;

    sql)
      # Format: sql <SELECT statement>
      #
      # DEFAULT: NOT EXECUTED, for the same reason as curl. psql reads the
      # statement from ITS OWN STDIN as if typed, which means backslash
      # meta-commands are live there — `\!` is a shell escape — so piping a
      # markdown-sourced string into psql is the curl bug one layer over,
      # with a DB connection attached. Classified UNVERIFIABLE before $rest
      # is inspected at all.
      if [[ "$_RVE_ALLOW_EXEC" -ne 1 ]]; then
        UNVERIFIABLE+="  UNVERIFIABLE: '$line' — 'sql' evidence is not executed (piping a markdown-sourced statement into psql executes content, and psql's \\! is a shell escape). Re-run this executor manually with --allow-exec to run it, or cite the change with a 'file <path>::<pattern>' line the gate can check by reading."$'\n'
        UNVERIF_COUNT=$((UNVERIF_COUNT + 1))
        continue
      fi
      # --- from here on: the operator explicitly opted in with --allow-exec.
      #
      # Previously this SKIP-ed with PASS if $SUPABASE_TEST_DB_URL or psql
      # was missing. That was a free-pass loophole: any evidence could ship
      # `sql SELECT ...` in a DB-less environment and auto-PASS. The fix:
      # missing env or missing psql is a FAIL, not a SKIP. The builder is
      # responsible for providing verification the harness can actually run.
      if [[ -z "$rest" ]]; then
        FAILURES+="  INVALID: '$line' — empty SQL statement"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      if [[ -z "${SUPABASE_TEST_DB_URL:-}" ]]; then
        FAILURES+="  FAIL: '$line' — SUPABASE_TEST_DB_URL not set. SQL verification cannot be executed. Either set the env var or use a different Runtime verification format (curl/test/playwright/file)."$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      if ! command -v psql >/dev/null 2>&1; then
        FAILURES+="  FAIL: '$line' — psql not installed. SQL verification cannot be executed. Install postgresql-client or use a different Runtime verification format."$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # Bounded: psql against an unreachable or wedged host blocks until its
      # own (absent by default) connect timeout. Unbounded work reachable
      # from a session-end hook is how a Stop turns into a hang; the curl
      # branch above has carried a bound for exactly this reason.
      if printf '%s\n' "$rest" | nl_run_bounded 15 psql "$SUPABASE_TEST_DB_URL" -q >/dev/null 2>&1; then
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        FAILURES+="  FAIL: '$line' — SQL statement errored against test DB (or exceeded the 15s bound)"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
      ;;

    file)
      # Format: file <path>::<line-pattern>
      if [[ "$rest" != *"::"* ]]; then
        FAILURES+="  INVALID: '$line' — expected 'file <path>::<line-pattern>'"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      file_path="${rest%%::*}"
      pattern="${rest#*::}"   # already annotation-stripped at the parse point

      # Reject trivially-matching patterns. The adversarial harness review
      # found that `file <any>::.*` trivially passes. Require that the
      # pattern contain at least 5 non-regex-meta characters to prove the
      # builder actually cited specific content.
      literal_chars=$(echo "$pattern" | tr -d '.*+?^$[](){}|\\')
      if [[ "${#literal_chars}" -lt 5 ]]; then
        FAILURES+="  INVALID: '$line' — pattern '$pattern' has fewer than 5 literal characters; specify a concrete substring of the code you claim to verify"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi

      # Reject patterns that are entirely metacharacters or would match any file
      if [[ "$pattern" == ".*" || "$pattern" == ".+" || "$pattern" == "^.*$" || "$pattern" == "^.+$" ]]; then
        FAILURES+="  INVALID: '$line' — pattern '$pattern' matches anything"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi

      resolved=$(_rve_resolve_path "$file_path")
      if [[ -z "$resolved" ]]; then
        UNVERIFIABLE+="  UNVERIFIABLE: '$line' — '$file_path' is a placeholder path, not a real file the executor can open"$'\n'
        UNVERIF_COUNT=$((UNVERIF_COUNT + 1))
        continue
      fi
      if [[ ! -f "$resolved" ]]; then
        FAILURES+="  FAIL: '$line' — file not found: $resolved"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi
      # `--` guards a pattern that begins with '-' (the repo's most-cited
      # symbol is literally `--self-test`); without it grep parses the
      # pattern as options and errors, reporting a false FAIL. -F first
      # (literal, the common case), then -E for genuine regex citations.
      if grep -qF -- "$pattern" "$resolved" 2>/dev/null || grep -qE -- "$pattern" "$resolved" 2>/dev/null; then
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        FAILURES+="  FAIL: '$line' — pattern '$pattern' not found in $resolved"$'\n'
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
      ;;

    *)
      # A format this executor cannot soundly execute (`command`, `bash`,
      # `functionality-verifier`, prose). Reported, never silently passed,
      # but not treated as a false claim either — see the UNVERIFIABLE note
      # in the header, and this unit's manifest bypass_paths.
      UNVERIFIABLE+="  UNVERIFIABLE: '$line' — format '$fmt' is not executable by this gate. Executable formats: test, playwright, curl, sql, file."$'\n'
      UNVERIF_COUNT=$((UNVERIF_COUNT + 1))
      ;;
  esac
done <<< "$LINES"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "" >&2
  echo "runtime-verification-executor: $FAIL_COUNT failure(s), $PASS_COUNT pass(es), $UNVERIF_COUNT unverifiable" >&2
  echo "$FAILURES" >&2
  [[ -n "$UNVERIFIABLE" ]] && echo "$UNVERIFIABLE" >&2
  echo "This gate: ~/.claude/hooks/runtime-verification-executor.sh (source: adapters/claude-code/hooks/runtime-verification-executor.sh)" >&2
  exit 1
fi

echo "runtime-verification-executor: $PASS_COUNT verification(s) passed, $UNVERIF_COUNT unverifiable" >&2
[[ -n "$UNVERIFIABLE" ]] && echo "$UNVERIFIABLE" >&2
exit 0
