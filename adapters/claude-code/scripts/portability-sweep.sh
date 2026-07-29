#!/bin/bash
# portability-sweep.sh — run every self-test-capable harness script under ONE
# named interpreter, with bounded per-script and total runtime, and report
# pass / fail / timeout per script plus a summary.
#
# ============================================================
# WHY THIS EXISTS (plan docs/plans/macos-portability-2026-07.md, task M5)
# ============================================================
#
# The harness was authored on Windows (Git-bash, bash 5.x, GNU coreutils).
# On a stock Mac the system interpreter is Apple's bash 3.2.57 (2007) and the
# userland is BSD. An ad-hoc sweep during that plan's M0 measurement found
# 14 of 52 self-test-capable scripts FAILING on `/bin/bash` + BSD that passed
# on Homebrew bash 5.3 + GNU coreutils.
#
# That measurement script lived in a session scratchpad and is gone. Nothing
# in the repo could reproduce it, and nothing could tell you when the count
# got worse. Every GNU-ism added after M4 would therefore have been found the
# same way the first fourteen were: by an operator hitting it.
#
# This file is the measurement, committed. `harness-doctor.sh --portability`
# (also part of `--full`) runs it against a COMMITTED baseline and REDs when
# the failing set GROWS. The baseline is a reviewable text file, so raising it
# is a visible act in a diff rather than a number edited in a script.
#
# ============================================================
# WHAT IT DOES
# ============================================================
#
#   1. DISCOVERS scripts that genuinely advertise a `--self-test` entrypoint.
#      "Contains the string --self-test" is NOT the predicate: install.sh and
#      sync.sh mention it in comments, and invoking those with an unrecognized
#      argument runs their NORMAL path — an installer, not a test. The
#      predicate is a real dispatch site (see _sw_has_selftest_entrypoint),
#      and its regex was derived from the actual dispatch lines in this repo,
#      not invented.
#
#   2. RUNS each one as `<interpreter> <script> --self-test </dev/null`, with
#      HARNESS_SELFTEST=1 NL_SELFTEST_SWEEP=1 (the same sandboxing/provenance
#      env harness-doctor.sh's own sweep uses), bounded by nl_run_bounded from
#      hooks/lib/portable-timeout.sh. This file does NOT hand-roll a second
#      bounding primitive; there is exactly one in this repo and this is a
#      caller of it.
#
#   3. MAKES THE INTERPRETER CLAIM TRUE. Almost every self-test suite in this
#      repo re-invokes itself as `bash "$SELF_TEST_HOOK" --self-test` — bare
#      `bash`, resolved from PATH. On a machine with Homebrew bash first on
#      PATH, `/bin/bash foo.sh --self-test` therefore reports "3.2" while its
#      children actually ran 5.3: the suite's reported interpreter is a lie,
#      and a sweep that trusted it would report green coverage it never had.
#      (This is not hypothetical — one suite in this repo reported 35/0 for an
#      interpreter it never ran.)
#      Two things follow:
#        (a) a PATH shim directory is prepended so a child's bare `bash` execs
#            the chosen interpreter (disable with --no-shim);
#        (b) every script whose body re-invokes bare `bash` is FLAGGED in the
#            report, because with --no-shim its result is interpreter-unsound.
#
#   4. BOUNDS TOTAL RUNTIME. Some suites take minutes (plan-reviewer.sh was
#      measured green-but-slow at 987s standalone). Scripts run in sorted
#      order so the tail that a budget cuts off is deterministic, and every
#      cut-off script is reported explicitly as SKIP(budget) — never silently
#      counted as passing.
#
# ============================================================
# USAGE
# ============================================================
#
#   portability-sweep.sh [options]
#
#     -i, --interpreter PATH   interpreter to run each suite under.
#                              Default: /bin/bash when executable (the stock
#                              system interpreter is the portability-relevant
#                              one), else $BASH.
#     --per-script-timeout N   wall-clock bound per suite (default 90).
#     --total-budget N         wall-clock bound for the whole sweep
#                              (default 1800). 0 = no total bound.
#     --roots "a b c"          space-separated dirs under adapters/claude-code
#                              to scan (default "hooks hooks/lib scripts").
#                              attic/ (retired) and tests/ (standalone
#                              harnesses, not --self-test entrypoints) are
#                              deliberately out of the default scope.
#     --only SUBSTR            restrict to paths containing SUBSTR.
#     --baseline FILE          compare against a committed baseline; exit 1
#                              iff the failing set GREW (a failing script not
#                              named in the baseline).
#     --write-baseline FILE    write the current failing set as a baseline.
#     --repo-root PATH         override repo-root resolution.
#     --tsv                    machine-readable output (STATUS\tpath\tdetail).
#     --progress               stream one line per suite to STDERR as it
#                              finishes. Off by default so a caller that
#                              parses `2>&1` (harness-doctor.sh) sees only
#                              the report; on for a human watching a run that
#                              takes tens of minutes.
#     --list                   print the discovered scripts and exit.
#     --no-shim                do NOT force child `bash` to the chosen
#                              interpreter (results become interpreter-unsound
#                              for every script flagged bare-bash).
#     --self-test              this file's own suite.
#
#   Exit codes: 0 = no new failures (or, without --baseline, no failures at
#   all); 1 = failures / new failures; 2 = usage or setup error.
#
# Portability floor: bash 3.2.57 (Apple's /bin/bash) + BSD userland. No
# associative arrays, no mapfile/readarray, no ${x^^}, no `date -d`, no bare
# `timeout`, no suffix-less `sed -i`.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ---- the ONE bounding primitive (plan M3) --------------------------------
# Hard requirement, not a soft one: this tool's entire contract is "bounded".
# A missing lib must not degrade into an unbounded sweep of ~200 suites.
# shellcheck disable=SC1091
{ . "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! command -v nl_run_bounded >/dev/null 2>&1; then
  echo "portability-sweep: FATAL — hooks/lib/portable-timeout.sh not found or did not define nl_run_bounded." >&2
  echo "portability-sweep: this tool's contract is a BOUNDED sweep; it will not run unbounded. Looked in: $SCRIPT_DIR/../hooks/lib/portable-timeout.sh" >&2
  exit 2
fi

# ======================================================================
# Defaults
# ======================================================================
SW_INTERP=""
SW_PER_TIMEOUT=90
SW_TOTAL_BUDGET=1800
SW_ROOTS="hooks hooks/lib scripts"
SW_ONLY=""
SW_BASELINE=""
SW_WRITE_BASELINE=""
SW_REPO_ROOT="${NL_REPO_ROOT:-}"
SW_TSV=0
SW_PROGRESS=0
SW_LIST=0
SW_SHIM=1
SW_SELFTEST=0

# ======================================================================
# Arg parsing
# ======================================================================
while [ "$#" -gt 0 ]; do
  case "$1" in
    -i|--interpreter)        SW_INTERP="${2:-}"; shift 2 ;;
    --per-script-timeout)    SW_PER_TIMEOUT="${2:-}"; shift 2 ;;
    --total-budget)          SW_TOTAL_BUDGET="${2:-}"; shift 2 ;;
    --roots)                 SW_ROOTS="${2:-}"; shift 2 ;;
    --only)                  SW_ONLY="${2:-}"; shift 2 ;;
    --baseline)              SW_BASELINE="${2:-}"; shift 2 ;;
    --write-baseline)        SW_WRITE_BASELINE="${2:-}"; shift 2 ;;
    --repo-root)             SW_REPO_ROOT="${2:-}"; shift 2 ;;
    --tsv)                   SW_TSV=1; shift ;;
    --progress)              SW_PROGRESS=1; shift ;;
    --list)                  SW_LIST=1; shift ;;
    --no-shim)               SW_SHIM=0; shift ;;
    --self-test)             SW_SELFTEST=1; shift ;;
    # Print the USAGE block by MARKER, never by line number: a line-numbered
    # `sed -n '68,100p'` silently starts printing the wrong paragraph the
    # first time anyone edits the header above it.
    -h|--help)               sed -n '/^# USAGE$/,/^# Portability floor/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "portability-sweep: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done

# ======================================================================
# resolve_repo_root — same tier order harness-doctor.sh uses.
# ======================================================================
_sw_resolve_repo_root() {
  local root
  if [ -n "$SW_REPO_ROOT" ]; then printf '%s\n' "$SW_REPO_ROOT"; return 0; fi
  root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$root" ]; then printf '%s\n' "$root"; return 0; fi
  local cfg="${HOME:-}/.claude/local/nl-repo-path"
  if [ -f "$cfg" ]; then
    root="$(head -1 "$cfg" | tr -d '\r\n')"
    if [ -n "$root" ] && [ -d "$root" ]; then printf '%s\n' "$root"; return 0; fi
  fi
  # Live mirror ($HOME/.claude) is not a git repo and has no adapters/ prefix;
  # callers that want it pass --repo-root explicitly.
  return 1
}

# ======================================================================
# _sw_has_selftest_entrypoint <file> — does this script REALLY dispatch on
# --self-test?
#
# The regex below was derived by enumerating every non-comment line
# mentioning --self-test across hooks/, scripts/, attic/ and tests/ in this
# repo and collapsing them into shapes. The shapes that exist here are:
#
#     if [[ "${1:-}" == "--self-test" ]]; then            (55 files)
#     --self-test)                                        (25 case arms)
#     if [ "${1:-}" = "--self-test" ]; then                (20)
#     if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]
#     --self-test|--selftest|selftest|self-test)
#     --self-test) SELF_TEST=1; shift ;;
#     [[ "$MODE" == "--self-test" ]]
#
# Two families cover all of them:
#   (A) a comparison whose right-hand side is --self-test:  =/== "--self-test"
#   (B) a case arm that STARTS with --self-test:            ^\s*--self-test[|)]
#
# Comment lines are excluded first, so a file that merely documents
# `foo.sh --self-test` in its header is not mistaken for one that implements
# it. That distinction is a SAFETY property, not a cosmetic one: running
# `install.sh --self-test` would run the installer.
# ======================================================================
_sw_has_selftest_entrypoint() {
  local f="$1"
  [ -f "$f" ] || return 1
  grep -v '^[[:space:]]*#' "$f" 2>/dev/null \
    | grep -qE '(==?[[:space:]]*"?--self-test"?)|(^[[:space:]]*--self-test[|)])'
}

# ======================================================================
# _sw_reinvokes_bare_bash <file> — does this script spawn `bash` resolved
# from PATH (rather than "$BASH" / an explicit interpreter path)?
#
# Such a script's own reported interpreter is a lie unless the sweep pins
# PATH's `bash` (which it does by default; see --no-shim).
#
# The regex is deliberately two-sided, because one-sided versions were both
# tried and both were wrong on REAL files in this repo:
#
#   - Left side only ("a `bash` token not preceded by / or $ or a word char")
#     fires on ordinary prose inside quoted strings — `echo "child bash
#     major=$x"` is not an invocation. Six such lines exist in THIS file.
#   - Stripping quoted spans first (the obvious fix) silently DESTROYS the
#     true positives: harness-doctor.sh's real call site is
#     `out="$(... nl_run_bounded "${T}" bash "$hook" --self-test ...)"`, whose
#     alternating quotes make ` bash ` fall inside a stripped span. Measured,
#     not assumed — that variant reported harness-doctor.sh as clean.
#
# So the right side must ALSO look like a bash argument: an option (`-c`,
# `--norc`), a quoted word, a `$var`, or a `*.sh` path. Prose continues with
# an ordinary English word and does not match.
#
# `$BASH`, `${BASH}`, `/bin/bash`, `/usr/bin/env bash` and `"$INTERP"`-style
# invocations are excluded by the left-hand character class: those pin the
# interpreter explicitly and are exactly what a portable suite should use.
# Full-line comments are dropped first.
# ======================================================================
_sw_reinvokes_bare_bash() {
  local f="$1"
  [ -f "$f" ] || return 1
  grep -v '^[[:space:]]*#' "$f" 2>/dev/null \
    | grep -qE '(^|[^-[:alnum:]_/${}"'"'"'.])bash[[:space:]]+(-[a-zA-Z-]|"|\$|'"'"'|[A-Za-z0-9_./-]*\.sh)'
}

# ======================================================================
# _sw_run_one <abs-path> <bound-seconds> — run one suite. Echoes nothing;
# leaves the combined output in $SW_RUN_OUT and returns the suite's rc
# (124 = killed by the bound, same as GNU timeout).
#
# Factored out of the main loop so the baseline comparison can RE-RUN a
# candidate regression. See the retry rationale where it is used.
# ======================================================================
SW_RUN_OUT=""
SW_RUN_PATH=""
_sw_run_one() {
  SW_RUN_OUT="$(nl_run_bounded "$2" env \
      HARNESS_SELFTEST=1 \
      NL_SELFTEST_SWEEP=1 \
      NL_PORTABILITY_SWEEP_ACTIVE=1 \
      "PATH=$SW_RUN_PATH" \
      "$SW_INTERP" "$1" --self-test </dev/null 2>&1)"
  return $?
}

# ======================================================================
# Set helpers — bash 3.2 has no associative arrays. Sets are "|a|b|c|"
# strings; harness paths never contain "|".
# ======================================================================
_sw_set_add() { printf '%s%s|' "$1" "$2"; }
_sw_set_has() { case "$1" in *"|$2|"*) return 0 ;; esac; return 1; }

# ======================================================================
# Discovery
# ======================================================================
_sw_discover() {
  local repo_cc="$1" roots="$2" only="$3"
  local root d f rel
  for root in $roots; do
    d="$repo_cc/$root"
    [ -d "$d" ] || continue
    for f in "$d"/*.sh; do
      [ -f "$f" ] || continue
      rel="${f#$repo_cc/}"
      if [ -n "$only" ]; then
        case "$rel" in *"$only"*) : ;; *) continue ;; esac
      fi
      _sw_has_selftest_entrypoint "$f" || continue
      printf '%s\n' "$rel"
    done
  done | LC_ALL=C sort
}

# ======================================================================
# Baseline I/O
#
# Format (one entry per line, tab-separated, sorted; `#` comments allowed):
#     <STATUS><TAB><path relative to adapters/claude-code>
# Only the PATH set is compared. A script that moves FAIL -> TIMEOUT is still
# a known-failing script, not a regression; the status is carried for the
# reader's benefit and reported as a drift WARN, never a RED.
# ======================================================================
_sw_baseline_paths() {
  local file="$1" line rest
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    # strip a leading STATUS field if present
    rest="$(printf '%s' "$line" | tr '\t' ' ')"
    case "$rest" in
      'PASS '*|'FAIL '*|'TIMEOUT '*|'SKIP '*) rest="${rest#* }" ;;
    esac
    rest="$(printf '%s' "$rest" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$rest" ] && printf '%s\n' "$rest"
  done < "$file"
}

_sw_baseline_status_for() {
  local file="$1" want="$2" line st p
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    st="$(printf '%s' "$line" | tr '\t' ' ' | sed -e 's/[[:space:]].*$//')"
    p="$(printf '%s' "$line" | tr '\t' ' ' | sed -e 's/^[^[:space:]]*[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ "$p" = "$want" ]; then printf '%s' "$st"; return 0; fi
  done < "$file"
  return 0
}

# ======================================================================
# --self-test  (defined below the helpers, dispatched here)
# ======================================================================
if [ "$SW_SELFTEST" = "1" ]; then
  # shellcheck disable=SC1091
  SW_SELFTEST_MAIN=1
fi

# ======================================================================
# MAIN
# ======================================================================
_sw_main() {
  local repo_root repo_cc
  repo_root="$(_sw_resolve_repo_root)" || {
    echo "portability-sweep: FATAL — cannot resolve repo root (pass --repo-root)" >&2
    return 2
  }
  repo_cc="$repo_root/adapters/claude-code"
  if [ ! -d "$repo_cc" ]; then
    # Allow pointing directly at a live mirror / bare adapter dir.
    if [ -d "$repo_root/hooks" ]; then
      repo_cc="$repo_root"
    else
      echo "portability-sweep: FATAL — no adapters/claude-code (or hooks/) under '$repo_root'" >&2
      return 2
    fi
  fi

  # ---- interpreter ----
  if [ -z "$SW_INTERP" ]; then
    if [ -x /bin/bash ]; then SW_INTERP=/bin/bash; else SW_INTERP="${BASH:-bash}"; fi
  fi
  if [ ! -x "$SW_INTERP" ]; then
    local resolved
    resolved="$(command -v "$SW_INTERP" 2>/dev/null)"
    if [ -n "$resolved" ]; then
      SW_INTERP="$resolved"
    else
      echo "portability-sweep: FATAL — interpreter '$SW_INTERP' is not executable" >&2
      return 2
    fi
  fi
  local interp_ver
  interp_ver="$("$SW_INTERP" --version 2>/dev/null | head -1)"
  [ -n "$interp_ver" ] || interp_ver="(version unknown)"

  # ---- numeric hygiene: a garbage bound must never mean "unbounded" ----
  case "$SW_PER_TIMEOUT" in ''|*[!0-9]*) SW_PER_TIMEOUT=90 ;; esac
  [ "$SW_PER_TIMEOUT" -lt 1 ] && SW_PER_TIMEOUT=1
  case "$SW_TOTAL_BUDGET" in ''|*[!0-9]*) SW_TOTAL_BUDGET=1800 ;; esac

  # ---- discovery ----
  local scripts
  scripts="$(_sw_discover "$repo_cc" "$SW_ROOTS" "$SW_ONLY")"
  if [ "$SW_LIST" = "1" ]; then
    printf '%s\n' "$scripts"
    return 0
  fi
  if [ -z "$scripts" ]; then
    echo "portability-sweep: no self-test-capable scripts discovered under roots '$SW_ROOTS' in $repo_cc" >&2
    return 2
  fi

  # ---- PATH shim: make a child's bare `bash` BE the chosen interpreter ----
  local shim_dir=""
  SW_RUN_PATH="$PATH"
  if [ "$SW_SHIM" = "1" ]; then
    shim_dir="$(mktemp -d 2>/dev/null || mktemp -d -t portability-sweep)"
    if [ -n "$shim_dir" ] && [ -d "$shim_dir" ]; then
      # `exec` the ABSOLUTE interpreter path — never `bash`, which would
      # re-enter this shim and fork-bomb.
      printf '#!/bin/sh\nexec %s "$@"\n' "$SW_INTERP" > "$shim_dir/bash"
      chmod +x "$shim_dir/bash"
      SW_RUN_PATH="$shim_dir:$PATH"
    else
      shim_dir=""
      echo "portability-sweep: WARN — could not create the PATH shim; child \`bash\` invocations will NOT be pinned to $SW_INTERP" >&2
    fi
  fi
  # shellcheck disable=SC2064
  trap "[ -n \"$shim_dir\" ] && rm -rf \"$shim_dir\"" EXIT

  # ---- run ----
  local t0=$SECONDS
  local n_discovered
  n_discovered="$(printf '%s\n' "$scripts" | grep -c '.')"
  local n_total=0 n_pass=0 n_fail=0 n_timeout=0 n_skip=0 n_barebash=0
  local failset="|" barebash_list="" rows=""
  local rel abs out rc bound elapsed remaining detail status started

  # Deterministic cwd: suites that resolve paths relative to $PWD must not
  # get a different answer depending on where the sweep was invoked.
  cd "$repo_root" 2>/dev/null || true

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    n_total=$(( n_total + 1 ))
    abs="$repo_cc/$rel"

    if _sw_reinvokes_bare_bash "$abs"; then
      n_barebash=$(( n_barebash + 1 ))
      barebash_list="$barebash_list$rel
"
    fi

    # Total-budget gate. Deterministic order means the cut-off tail is stable.
    if [ "$SW_TOTAL_BUDGET" -gt 0 ]; then
      remaining=$(( SW_TOTAL_BUDGET - ( SECONDS - t0 ) ))
      if [ "$remaining" -le 0 ]; then
        n_skip=$(( n_skip + 1 ))
        rows="$rows	SKIP	$rel	total budget (${SW_TOTAL_BUDGET}s) exhausted before this script ran
"
        [ "$SW_PROGRESS" = "1" ] && printf '[%3s/%3s] %-7s %s\n' "$n_total" "$n_discovered" "SKIP" "$rel" >&2
        continue
      fi
      bound="$SW_PER_TIMEOUT"
      [ "$bound" -gt "$remaining" ] && bound="$remaining"
    else
      bound="$SW_PER_TIMEOUT"
    fi

    started=$SECONDS
    _sw_run_one "$abs" "$bound"
    rc=$?
    out="$SW_RUN_OUT"
    elapsed=$(( SECONDS - started ))

    if [ "$rc" -eq 0 ]; then
      status=PASS; n_pass=$(( n_pass + 1 )); detail="${elapsed}s"
    elif [ "$rc" -eq 124 ]; then
      status=TIMEOUT; n_timeout=$(( n_timeout + 1 )); detail=">${bound}s — killed"
      failset="$(_sw_set_add "$failset" "$rel")"
    else
      status=FAIL; n_fail=$(( n_fail + 1 ))
      detail="rc=$rc ${elapsed}s | $(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 1 | cut -c1-160)"
      failset="$(_sw_set_add "$failset" "$rel")"
    fi
    rows="$rows	$status	$rel	$detail
"
    [ "$SW_PROGRESS" = "1" ] && printf '[%3s/%3s] %-7s %s\n' "$n_total" "$n_discovered" "$status" "$rel" >&2
  done <<_SW_SCRIPTS
$scripts
_SW_SCRIPTS

  local total_elapsed=$(( SECONDS - t0 ))

  # ---- report ----
  if [ "$SW_TSV" = "1" ]; then
    printf '%s' "$rows" | sed -e 's/^	//'
    printf 'SUMMARY\t-\tinterpreter=%s discovered=%s pass=%s fail=%s timeout=%s skip=%s barebash=%s elapsed=%ss\n' \
      "$SW_INTERP" "$n_total" "$n_pass" "$n_fail" "$n_timeout" "$n_skip" "$n_barebash" "$total_elapsed"
  else
    echo "portability-sweep"
    echo "  interpreter : $SW_INTERP — $interp_ver"
    if [ "$SW_SHIM" = "1" ] && [ -n "$shim_dir" ]; then
      echo "  child bash  : PINNED to $SW_INTERP via PATH shim (so a suite that re-invokes bare \`bash\` still runs the interpreter this report names)"
    else
      echo "  child bash  : NOT pinned (--no-shim) — every bare-bash script below reports an interpreter it may not have run"
    fi
    echo "  repo        : $repo_cc"
    echo "  roots       : $SW_ROOTS${SW_ONLY:+   (filtered: *$SW_ONLY*)}"
    echo "  bounds      : ${SW_PER_TIMEOUT}s per script, ${SW_TOTAL_BUDGET}s total"
    echo ""
    printf '%s' "$rows" | sed -e 's/^	//' | while IFS='	' read -r st p d; do
      [ -n "$st" ] || continue
      case "$st" in
        PASS) continue ;;
        *) printf '  %-7s %-52s %s\n' "$st" "$p" "$d" ;;
      esac
    done
    if [ "$n_fail" -eq 0 ] && [ "$n_timeout" -eq 0 ] && [ "$n_skip" -eq 0 ]; then
      echo "  (no failures, timeouts or skips)"
    fi
    echo ""
    echo "  discovered=$n_total  pass=$n_pass  fail=$n_fail  timeout=$n_timeout  skip=$n_skip  elapsed=${total_elapsed}s"
    if [ "$n_barebash" -gt 0 ]; then
      echo "  interpreter-unsound-without-shim: $n_barebash script(s) re-invoke bare \`bash\`"
      printf '%s' "$barebash_list" | head -8 | sed -e 's/^/      /'
      [ "$n_barebash" -gt 8 ] && echo "      … and $(( n_barebash - 8 )) more"
    fi
  fi

  # ---- baseline write ----
  if [ -n "$SW_WRITE_BASELINE" ]; then
    {
      echo "# portability-baseline.txt — the KNOWN-FAILING self-test set."
      echo "#"
      echo "# Generated by: adapters/claude-code/scripts/portability-sweep.sh --write-baseline"
      echo "# Consumed by : adapters/claude-code/hooks/harness-doctor.sh (check portability-sweep)"
      echo "#"
      echo "# The doctor REDs when a script FAILS or TIMES OUT and is NOT listed here."
      echo "# Adding a line to this file is therefore an explicit, reviewable act of"
      echo "# accepting a known-broken suite — not a number quietly edited in a script."
      echo "#"
      echo "# This is a DEBT LIST, not an approval. Every line is a self-test that does"
      echo "# not pass on the interpreter named below — a real defect someone has to fix."
      echo "# Shrinking the list is the work; growing it needs a reason in the commit"
      echo "# message that adds the line."
      echo "#"
      echo "# Regenerate:"
      echo "#   bash adapters/claude-code/scripts/portability-sweep.sh \\"
      echo "#        --write-baseline docs/portability-baseline.txt"
      echo "#"
      echo "# Regeneration reflects ONE run, so a load-sensitive suite can drop out of it."
      echo "# Adding a line by hand is sanctioned — it is exactly the 'explicit, reviewable"
      echo "# act' this file exists to make visible. Keep the list sorted by path, and say"
      echo "# in the commit message why the line is there."
      echo "#"
      echo "# Measured: interpreter=$SW_INTERP  ($interp_ver)"
      echo "#           roots=\"$SW_ROOTS\"  per-script-timeout=${SW_PER_TIMEOUT}s  total-budget=${SW_TOTAL_BUDGET}s"
      echo "#           discovered=$n_total pass=$n_pass fail=$n_fail timeout=$n_timeout skip=$n_skip"
      echo "#"
      echo "# Format: <STATUS><TAB><path relative to adapters/claude-code>"
      printf '%s' "$rows" | sed -e 's/^	//' | while IFS='	' read -r st p d; do
        case "$st" in FAIL|TIMEOUT) printf '%s\t%s\n' "$st" "$p" ;; esac
      done | LC_ALL=C sort
    } > "$SW_WRITE_BASELINE"
    echo "  baseline written: $SW_WRITE_BASELINE"
  fi

  # ---- baseline comparison ----
  if [ -n "$SW_BASELINE" ]; then
    if [ ! -f "$SW_BASELINE" ]; then
      echo "portability-sweep: FATAL — baseline file not found: $SW_BASELINE" >&2
      return 2
    fi
    local baseset="|" bp new_fail="" stale="" drift="" flaky=""
    while IFS= read -r bp; do
      [ -n "$bp" ] || continue
      baseset="$(_sw_set_add "$baseset" "$bp")"
    done <<_SW_BASE
$(_sw_baseline_paths "$SW_BASELINE")
_SW_BASE

    local st p d
    while IFS='	' read -r st p d; do
      [ -n "$st" ] || continue
      case "$st" in
        FAIL|TIMEOUT)
          if _sw_set_has "$baseset" "$p"; then
            local was
            was="$(_sw_baseline_status_for "$SW_BASELINE" "$p")"
            [ -n "$was" ] && [ "$was" != "$st" ] && drift="$drift  $p: baseline says $was, now $st
"
          else
            # RETRY BEFORE CALLING IT A REGRESSION.
            #
            # Measured, not defensive programming: four independent full
            # sweeps of this repo produced an identical verdict for 163 of
            # 164 scripts; exactly one (scripts/coord-sync.sh) failed on run
            # 4 and passed on runs 1-3 and again standalone. A check that
            # REDs on any single failing run therefore cries wolf roughly
            # once every few runs — and a doctor the operator learns to
            # ignore is worse than no doctor.
            #
            # Only candidate REGRESSIONS are re-run, so the normal (green)
            # path costs nothing. A suite that fails twice in a row is
            # reported; one that passes on the retry is reported as FLAKY —
            # loudly, because a flaky self-test is itself a defect — but it
            # does not claim a regression it cannot substantiate.
            local rrc
            _sw_run_one "$repo_cc/$p" "$SW_PER_TIMEOUT"
            rrc=$?
            if [ "$rrc" -eq 0 ]; then
              flaky="$flaky  $p — failed once ($st), PASSED on retry; not counted as a regression, but a flaky self-test is a defect: fix it or baseline it
"
            else
              # The "REGRESSION" marker is not decoration: harness-doctor.sh
              # parses this output line-by-line, and its first version matched
              # on "  FAIL  " — which ALSO matches every row of the report
              # body above, so a single real regression came back as 54 REDs
              # with the true one buried at the bottom. Found by running the
              # injected-regression demo, not by reading the code. Keep this
              # token unique to this section.
              new_fail="$new_fail  REGRESSION $st $p — $d
"
            fi
          fi
          ;;
        PASS)
          _sw_set_has "$baseset" "$p" && stale="$stale  $p
"
          ;;
      esac
    done <<_SW_ROWS
$(printf '%s' "$rows" | sed -e 's/^	//')
_SW_ROWS

    echo ""
    echo "  baseline: $SW_BASELINE"
    # Interpreter provenance. A baseline measured on Apple's bash 3.2 will
    # legitimately show dozens of entries passing when the same check runs on
    # a GNU bash 5.x machine — that is the whole point of the baseline, not
    # rot. Calling that "STALE" there would train the operator to ignore the
    # word on the one machine where it means something. So the STALE marker
    # (which is what harness-doctor.sh WARNs on) is emitted ONLY when the
    # baseline was measured on the same interpreter build we just ran.
    local base_ver
    base_ver="$(grep -m1 '^# Measured: interpreter=' "$SW_BASELINE" 2>/dev/null | sed -e 's/^[^(]*(//' -e 's/)[[:space:]]*$//')"
    if [ -n "$stale" ] && [ -n "$base_ver" ] && [ "$base_ver" != "$interp_ver" ]; then
      echo "  baseline was measured on a DIFFERENT interpreter build:"
      echo "      baseline: $base_ver"
      echo "      this run: $interp_ver"
      echo "  entries below pass HERE and are expected to — not rot, and not reported as stale:"
      printf '%s' "$stale"
    elif [ -n "$stale" ]; then
      echo "  baseline STALE — these are listed as known-failing but now PASS (remove them):"
      printf '%s' "$stale"
    fi
    if [ -n "$drift" ]; then
      echo "  baseline status drift (still failing, different mode — not a regression):"
      printf '%s' "$drift"
    fi
    if [ -n "$flaky" ]; then
      echo "  FLAKY (failed once, passed on retry — no regression claimed):"
      printf '%s' "$flaky"
    fi
    if [ -n "$new_fail" ]; then
      echo "  NEW FAILURES (not in the baseline) — this is the regression condition:"
      printf '%s' "$new_fail"
      return 1
    fi
    echo "  no new failures relative to the baseline."
    return 0
  fi

  if [ "$n_fail" -gt 0 ] || [ "$n_timeout" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ======================================================================
# --self-test
# ======================================================================
if [ "${SW_SELFTEST_MAIN:-0}" = "1" ]; then
  PASSED=0
  FAILED=0
  _p() { printf 'self-test (%s): PASS\n' "$1" >&2; PASSED=$((PASSED+1)); }
  _f() { printf 'self-test (%s): FAIL — %s\n' "$1" "$2" >&2; FAILED=$((FAILED+1)); }

  SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
  # NEVER re-invoke via bare `bash`: that silently runs whichever interpreter
  # is first on PATH, so the suite's reported interpreter would be a lie —
  # the exact defect this file exists to detect.
  ME="${BASH:-/bin/bash}"

  TMPROOT="$(mktemp -d 2>/dev/null || mktemp -d -t portability-sweep-st)"
  if [ -z "$TMPROOT" ] || [ ! -d "$TMPROOT" ]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  REAL_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
  REAL_CC=""
  [ -n "$REAL_ROOT" ] && [ -d "$REAL_ROOT/adapters/claude-code" ] && REAL_CC="$REAL_ROOT/adapters/claude-code"

  # ------------------------------------------------------------------
  # D1-D4 — the DISCOVERY predicate, checked against REAL repo artifacts.
  # Hand-written fixtures would only prove the regex matches what I wrote;
  # this repo already contains every dispatch shape, so the real files are
  # the oracle. (Two Critical defects in this repo were masked by
  # author-written fixtures; see the plan.)
  # ------------------------------------------------------------------
  if [ -n "$REAL_CC" ]; then
    # D1 — `if [[ "${1:-}" == "--self-test" ]]` shape (harness-doctor.sh)
    if _sw_has_selftest_entrypoint "$REAL_CC/hooks/harness-doctor.sh"; then
      _p "D1 real-dispatch-double-bracket (hooks/harness-doctor.sh)"
    else _f "D1 real-dispatch-double-bracket" "harness-doctor.sh not detected"; fi

    # D2 — `[ ... ] && [ "${1:-}" = "--self-test" ]` shape, in a LIB (the
    # scope the doctor's old sweep could never see).
    if _sw_has_selftest_entrypoint "$REAL_CC/hooks/lib/portable-timeout.sh"; then
      _p "D2 real-dispatch-single-bracket-lib (hooks/lib/portable-timeout.sh)"
    else _f "D2 real-dispatch-single-bracket-lib" "portable-timeout.sh not detected"; fi

    # D3 — a case-arm dispatch, found from the real tree rather than assumed.
    _D3=""
    for _c in "$REAL_CC"/scripts/*.sh "$REAL_CC"/hooks/*.sh; do
      [ -f "$_c" ] || continue
      if grep -v '^[[:space:]]*#' "$_c" 2>/dev/null | grep -qE '^[[:space:]]*--self-test[|)]'; then
        _D3="$_c"; break
      fi
    done
    if [ -n "$_D3" ]; then
      if _sw_has_selftest_entrypoint "$_D3"; then
        _p "D3 real-dispatch-case-arm ($(basename "$_D3"))"
      else _f "D3 real-dispatch-case-arm" "$_D3 has a case arm but was not detected"; fi
    else
      _f "D3 real-dispatch-case-arm" "no case-arm dispatch found in the real repo — the shape survey is stale"
    fi

    # D4 — THE SAFETY PROPERTY. install.sh mentions --self-test only in prose;
    # it must NOT be discovered, because invoking it with an unrecognized
    # argument runs the INSTALLER. A string-contains predicate (which the
    # doctor's older sweep uses) fails this.
    if grep -q -- '--self-test' "$REAL_CC/install.sh" 2>/dev/null; then
      if _sw_has_selftest_entrypoint "$REAL_CC/install.sh"; then
        _f "D4 mentions-but-does-not-dispatch-excluded" "install.sh was discovered — running it with --self-test would run the INSTALLER"
      else
        _p "D4 mentions-but-does-not-dispatch-excluded (install.sh)"
      fi
    else
      _f "D4 mentions-but-does-not-dispatch-excluded" "install.sh no longer mentions --self-test; pick a new real negative"
    fi

    # D5 — hooks/lib IS in the default roots. This is the scope hole the
    # doctor's own sweep had: it globs hooks/*.sh, which never matches
    # hooks/lib/*.sh, so ~21 libs' assertions never ran.
    _LIBS="$(_sw_discover "$REAL_CC" "hooks/lib" "")"
    _NLIBS="$(printf '%s\n' "$_LIBS" | grep -c 'hooks/lib/' || true)"
    if [ "${_NLIBS:-0}" -ge 5 ]; then
      _p "D5 hooks/lib-in-scope ($_NLIBS libs discovered)"
    else _f "D5 hooks/lib-in-scope" "only ${_NLIBS:-0} libs discovered — the lib scope is not covered"; fi

    # D6 — bare-bash detection, against REAL positives and REAL negatives.
    # No hand-written fixture: this repo contains both classes already.
    #
    # D6a positive: harness-doctor.sh's sweep really does run
    #   `nl_run_bounded "$T" bash "$hook" --self-test`.
    if _sw_reinvokes_bare_bash "$REAL_CC/hooks/harness-doctor.sh"; then
      _p "D6a bare-bash-detected (hooks/harness-doctor.sh)"
    else _f "D6a bare-bash-detected" "harness-doctor.sh re-invokes bare bash but was not flagged"; fi

    # D6b negative: a REAL lib that never spawns an interpreter at all. Chosen
    # dynamically (no `bash` token anywhere outside comments) so this does not
    # rot the moment that particular file changes; the assertion is that such
    # a file exists AND is not flagged.
    _D6NEG=""
    for _c in "$REAL_CC"/hooks/lib/*.sh "$REAL_CC"/hooks/*.sh; do
      [ -f "$_c" ] || continue
      grep -v '^[[:space:]]*#' "$_c" 2>/dev/null | grep -q 'bash' && continue
      _D6NEG="$_c"; break
    done
    if [ -z "$_D6NEG" ]; then
      _f "D6b bare-bash-not-overreported" "no bash-free real script found — the negative went UNTESTED"
    elif _sw_reinvokes_bare_bash "$_D6NEG"; then
      _f "D6b bare-bash-not-overreported" "$(basename "$_D6NEG") contains no bash token at all yet was flagged"
    else
      _p "D6b bare-bash-not-overreported ($(basename "$_D6NEG"))"
    fi

    # D6c partition sanity: a detector that flags EVERY script (or none) is
    # useless whichever way it errs, and both failure modes were hit while
    # building this. Assert it genuinely splits the real corpus, and that the
    # flagged share is not absurd (>90% means the prose false-positive class
    # is back).
    _D6ALL=0; _D6HIT=0
    while IFS= read -r _r; do
      [ -n "$_r" ] || continue
      _D6ALL=$(( _D6ALL + 1 ))
      _sw_reinvokes_bare_bash "$REAL_CC/$_r" && _D6HIT=$(( _D6HIT + 1 ))
    done <<_SW_D6
$(_sw_discover "$REAL_CC" "hooks hooks/lib scripts" "")
_SW_D6
    if [ "$_D6ALL" -lt 20 ]; then
      _f "D6c bare-bash-partitions-the-real-corpus" "only $_D6ALL scripts discovered — corpus too small to judge"
    elif [ "$_D6HIT" -eq 0 ]; then
      _f "D6c bare-bash-partitions-the-real-corpus" "0 of $_D6ALL flagged — the detector is dead"
    elif [ "$(( _D6HIT * 10 ))" -gt "$(( _D6ALL * 9 ))" ]; then
      _f "D6c bare-bash-partitions-the-real-corpus" "$_D6HIT of $_D6ALL flagged (>90%) — prose false positives are back"
    else
      _p "D6c bare-bash-partitions-the-real-corpus ($_D6HIT of $_D6ALL flagged)"
    fi
  else
    _f "D1-D6 real-artifact-discovery" "cannot resolve the real repo — discovery predicate went UNTESTED"
  fi

  # ------------------------------------------------------------------
  # Sandbox fixture repo: a passing suite, a failing suite, a slow suite,
  # and a prose-only script. These are stubs on purpose — they exercise the
  # RUNNER's classification, not the discovery regex (which is tested above
  # against real artifacts).
  # ------------------------------------------------------------------
  FX="$TMPROOT/fx"
  mkdir -p "$FX/adapters/claude-code/hooks" "$FX/adapters/claude-code/hooks/lib"
  cat > "$FX/adapters/claude-code/hooks/aa-pass.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then echo "ok"; exit 0; fi
exit 0
EOF
  cat > "$FX/adapters/claude-code/hooks/bb-fail.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then echo "self-test summary: 1 passed, 2 failed" >&2; exit 1; fi
exit 0
EOF
  cat > "$FX/adapters/claude-code/hooks/cc-slow.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then sleep 45; exit 0; fi
exit 0
EOF
  cat > "$FX/adapters/claude-code/hooks/lib/dd-lib-pass.sh" <<'EOF'
#!/bin/bash
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ] && [ "${1:-}" = "--self-test" ]; then echo ok; exit 0; fi
EOF
  chmod +x "$FX/adapters/claude-code/hooks"/*.sh "$FX/adapters/claude-code/hooks/lib"/*.sh

  RUN() { "$ME" "$SELF" --repo-root "$FX" --roots "hooks hooks/lib" "$@"; }

  # R1 — classification: PASS / FAIL / TIMEOUT all appear, and the lib is run.
  OUT="$(RUN --per-script-timeout 2 --tsv 2>&1)"; RC=$?
  if printf '%s' "$OUT" | grep -q '^FAIL	hooks/bb-fail.sh'; then _p "R1a fail-classified"; else _f "R1a fail-classified" "$OUT"; fi
  if printf '%s' "$OUT" | grep -q '^TIMEOUT	hooks/cc-slow.sh'; then _p "R1b timeout-classified"; else _f "R1b timeout-classified" "$OUT"; fi
  if printf '%s' "$OUT" | grep -q '^PASS	hooks/aa-pass.sh'; then _p "R1c pass-classified"; else _f "R1c pass-classified" "$OUT"; fi
  if printf '%s' "$OUT" | grep -q '^PASS	hooks/lib/dd-lib-pass.sh'; then _p "R1d lib-actually-run"; else _f "R1d lib-actually-run" "$OUT"; fi
  if [ "$RC" -eq 1 ]; then _p "R1e nonzero-exit-on-failures"; else _f "R1e nonzero-exit-on-failures" "rc=$RC"; fi

  # R2 — a suite killed by the per-script bound leaves nothing running.
  # (The bound is nl_run_bounded's; this asserts the SWEEP wires it up, which
  # is the only way a 200-suite sweep stays bounded.)
  _LEFT="$(ps -A -o command= 2>/dev/null | grep -c '[c]c-slow.sh' || true)"
  _LEFT="$(printf '%s' "$_LEFT" | tr -d ' ')"
  case "$_LEFT" in ''|*[!0-9]*) _LEFT=0 ;; esac
  if [ "$_LEFT" -eq 0 ]; then _p "R2 timed-out-suite-reaped"; else _f "R2 timed-out-suite-reaped" "$_LEFT cc-slow.sh still running"; fi

  # R3 — BASELINE COMPARISON, the doctor's actual RED condition.
  BL="$TMPROOT/baseline.txt"
  printf 'FAIL\thooks/bb-fail.sh\nTIMEOUT\thooks/cc-slow.sh\n' > "$BL"
  OUT="$(RUN --per-script-timeout 2 --baseline "$BL" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ]; then _p "R3a known-failures-are-not-a-regression"; else _f "R3a known-failures-are-not-a-regression" "rc=$RC: $OUT"; fi

  # R3b — a NEW failing script (not in the baseline) MUST be a regression.
  cat > "$FX/adapters/claude-code/hooks/ee-new-fail.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then echo "boom" >&2; exit 1; fi
exit 0
EOF
  chmod +x "$FX/adapters/claude-code/hooks/ee-new-fail.sh"
  OUT="$(RUN --per-script-timeout 2 --baseline "$BL" 2>&1)"; RC=$?
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'ee-new-fail.sh'; then
    _p "R3b new-failing-script-is-a-regression"
  else _f "R3b new-failing-script-is-a-regression" "rc=$RC: $OUT"; fi

  # R3c — a NEW *passing* script must NOT be a regression. (The symmetric
  # half: a check that REDs on any new script would be useless.)
  cat > "$FX/adapters/claude-code/hooks/ff-new-pass.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then echo fine; exit 0; fi
exit 0
EOF
  chmod +x "$FX/adapters/claude-code/hooks/ff-new-pass.sh"
  rm -f "$FX/adapters/claude-code/hooks/ee-new-fail.sh"
  OUT="$(RUN --per-script-timeout 2 --baseline "$BL" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ]; then _p "R3c new-passing-script-is-not-a-regression"; else _f "R3c new-passing-script-is-not-a-regression" "rc=$RC: $OUT"; fi

  # R3d — a baseline entry that now PASSES is reported as STALE (and does not
  # RED). Silence there would let the baseline rot into permanent amnesty.
  printf 'FAIL\thooks/aa-pass.sh\nFAIL\thooks/bb-fail.sh\nTIMEOUT\thooks/cc-slow.sh\n' > "$TMPROOT/bl2.txt"
  OUT="$(RUN --per-script-timeout 2 --baseline "$TMPROOT/bl2.txt" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'baseline STALE'; then
    _p "R3d stale-baseline-entry-surfaced"
  else _f "R3d stale-baseline-entry-surfaced" "rc=$RC: $OUT"; fi

  # R3f — RETRY BEFORE REGRESSION. A suite that fails once and passes on the
  # re-run is reported as FLAKY, not as a regression (rc stays 0). The stub
  # fails only on its FIRST invocation, using a marker file in the fixture —
  # so this exercises the real retry, not a mocked one. Paired with R3b (a
  # suite that fails BOTH times, which must still RED), the two together pin
  # the retry to "one extra chance", not "never fails".
  cat > "$FX/adapters/claude-code/hooks/hh-flaky.sh" <<EOF
#!/bin/bash
if [[ "\${1:-}" == "--self-test" ]]; then
  if [ -f "$TMPROOT/FLAKY_SEEN" ]; then echo "second run: ok"; exit 0; fi
  touch "$TMPROOT/FLAKY_SEEN"
  echo "first run: transient failure" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$FX/adapters/claude-code/hooks/hh-flaky.sh"
  rm -f "$TMPROOT/FLAKY_SEEN"
  OUT="$(RUN --per-script-timeout 5 --baseline "$BL" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'FLAKY' && printf '%s' "$OUT" | grep -q 'hh-flaky.sh'; then
    _p "R3f flaky-suite-retried-not-called-a-regression"
  else
    _f "R3f flaky-suite-retried-not-called-a-regression" "rc=$RC: $OUT"
  fi
  # ...and the retry must NOT rescue a genuinely broken suite: with the
  # marker pre-created the stub passes outright, so re-add a hard failure and
  # confirm rc 1 still comes back.
  cat > "$FX/adapters/claude-code/hooks/ii-hard-fail.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then echo "always broken" >&2; exit 1; fi
exit 0
EOF
  chmod +x "$FX/adapters/claude-code/hooks/ii-hard-fail.sh"
  OUT="$(RUN --per-script-timeout 5 --baseline "$BL" 2>&1)"; RC=$?
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'ii-hard-fail.sh'; then
    _p "R3g retry-does-not-rescue-a-consistently-failing-suite"
  else
    _f "R3g retry-does-not-rescue-a-consistently-failing-suite" "rc=$RC: $OUT"
  fi
  rm -f "$FX/adapters/claude-code/hooks/hh-flaky.sh" "$FX/adapters/claude-code/hooks/ii-hard-fail.sh"

  # R3e — a baseline measured on a DIFFERENT interpreter build must NOT shout
  # STALE for entries that pass here. A bash-3.2 baseline checked on a GNU
  # bash 5.x machine legitimately shows dozens of passes; flagging those as
  # rot would train the operator to ignore the word on the one machine where
  # it means something. rc must still be 0 either way.
  {
    echo "# portability-baseline.txt"
    echo "# Measured: interpreter=/somewhere/bash  (GNU bash, version 0.0.0(1)-release (not-this-machine))"
    printf 'FAIL\thooks/aa-pass.sh\nFAIL\thooks/bb-fail.sh\nTIMEOUT\thooks/cc-slow.sh\n'
  } > "$TMPROOT/bl3.txt"
  OUT="$(RUN --per-script-timeout 2 --baseline "$TMPROOT/bl3.txt" 2>&1)"; RC=$?
  if [ "$RC" -ne 0 ]; then
    _f "R3e foreign-interpreter-baseline-not-called-stale" "rc=$RC: $OUT"
  elif printf '%s' "$OUT" | grep -q 'baseline STALE'; then
    _f "R3e foreign-interpreter-baseline-not-called-stale" "said STALE for a baseline measured elsewhere: $OUT"
  elif printf '%s' "$OUT" | grep -q 'DIFFERENT interpreter build'; then
    _p "R3e foreign-interpreter-baseline-not-called-stale"
  else
    _f "R3e foreign-interpreter-baseline-not-called-stale" "neither STALE nor the provenance note appeared: $OUT"
  fi

  # R4 — --write-baseline round-trips: writing then comparing is rc 0.
  OUT="$(RUN --per-script-timeout 2 --write-baseline "$TMPROOT/gen.txt" 2>&1)"
  if [ -s "$TMPROOT/gen.txt" ]; then _p "R4a baseline-written"; else _f "R4a baseline-written" "$OUT"; fi
  OUT="$(RUN --per-script-timeout 2 --baseline "$TMPROOT/gen.txt" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ]; then _p "R4b generated-baseline-round-trips"; else _f "R4b generated-baseline-round-trips" "rc=$RC: $OUT"; fi

  # R5 — TOTAL BUDGET. With a 1s total budget and a 45s suite in the middle,
  # the tail must come back as SKIP rather than being silently counted green.
  OUT="$(RUN --per-script-timeout 2 --total-budget 1 --tsv 2>&1)"
  if printf '%s' "$OUT" | grep -q '^SKIP	'; then _p "R5a budget-exhaustion-reports-SKIP"; else _f "R5a budget-exhaustion-reports-SKIP" "$OUT"; fi
  if printf '%s' "$OUT" | grep -q 'skip=0'; then _f "R5b budget-skips-counted" "summary claims skip=0: $OUT"; else _p "R5b budget-skips-counted"; fi

  # R6 — THE SHIM. A suite that re-invokes bare `bash` must report the
  # interpreter the sweep NAMES, not whatever is first on PATH. Run only when
  # two genuinely different bash majors exist on this machine; otherwise the
  # scenario cannot distinguish anything and says so rather than passing by
  # default.
  cat > "$FX/adapters/claude-code/hooks/gg-barebash.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then
  # deliberately bare `bash` — the pattern this sweep exists to catch
  child="$(bash -c 'echo "${BASH_VERSINFO[0]}"')"
  [ "$child" = "${EXPECT_MAJOR:-}" ] && exit 0
  echo "child bash major=$child expected=${EXPECT_MAJOR:-}" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$FX/adapters/claude-code/hooks/gg-barebash.sh"
  ALT=""
  for _cand in /opt/homebrew/bin/bash /usr/local/bin/bash /bin/bash; do
    [ -x "$_cand" ] || continue
    _maj="$("$_cand" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)"
    _sysmaj="$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)"
    if [ -n "$_maj" ] && [ -n "$_sysmaj" ] && [ "$_maj" != "$_sysmaj" ]; then ALT="$_cand"; break; fi
  done
  if [ -n "$ALT" ]; then
    ALTMAJ="$("$ALT" -c 'echo "${BASH_VERSINFO[0]}"')"
    SYSMAJ="$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')"
    # Shim ON, interpreter = the ALT: the child's bare `bash` must be ALT.
    OUT="$(EXPECT_MAJOR="$ALTMAJ" "$ME" "$SELF" --repo-root "$FX" --roots "hooks" \
             --only gg-barebash -i "$ALT" --per-script-timeout 20 --tsv 2>&1)"
    if printf '%s' "$OUT" | grep -q '^PASS	hooks/gg-barebash.sh'; then
      _p "R6a shim-pins-child-bash-to-the-named-interpreter (alt=$ALT major=$ALTMAJ)"
    else _f "R6a shim-pins-child-bash-to-the-named-interpreter" "$OUT"; fi
    # Same run with the SYSTEM interpreter: the child must be the system one.
    OUT="$(EXPECT_MAJOR="$SYSMAJ" "$ME" "$SELF" --repo-root "$FX" --roots "hooks" \
             --only gg-barebash -i /bin/bash --per-script-timeout 20 --tsv 2>&1)"
    if printf '%s' "$OUT" | grep -q '^PASS	hooks/gg-barebash.sh'; then
      _p "R6b shim-pins-child-bash-to-the-system-interpreter (major=$SYSMAJ)"
    else _f "R6b shim-pins-child-bash-to-the-system-interpreter" "$OUT"; fi
    # MUTATION CONTROL: with --no-shim the child follows PATH, so asking for
    # the interpreter that is NOT first on PATH must NOT pass. If this ever
    # passes, the shim is not what is doing the pinning and R6a/R6b prove
    # nothing.
    _PATHMAJ="$(bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)"
    _WANT="$ALTMAJ"; [ "$_PATHMAJ" = "$ALTMAJ" ] && _WANT="$SYSMAJ"
    _WANTINT="$ALT"; [ "$_PATHMAJ" = "$ALTMAJ" ] && _WANTINT=/bin/bash
    OUT="$(EXPECT_MAJOR="$_WANT" "$ME" "$SELF" --repo-root "$FX" --roots "hooks" \
             --only gg-barebash -i "$_WANTINT" --no-shim --per-script-timeout 20 --tsv 2>&1)"
    if printf '%s' "$OUT" | grep -q '^FAIL	hooks/gg-barebash.sh'; then
      _p "R6c no-shim-control-shows-the-lie (PATH bash major=$_PATHMAJ, asked for $_WANT)"
    else _f "R6c no-shim-control-shows-the-lie" "expected FAIL without the shim; got: $OUT"; fi
  else
    _f "R6 shim" "no second bash major on this machine — the shim went UNTESTED (install a second bash to cover it)"
  fi

  # R7 — a script that only MENTIONS --self-test is never executed. The
  # fixture writes a marker file if it is ever run with an unknown argument;
  # this asserts the marker's ABSENCE, which is legitimate here because the
  # feature under test is precisely "we never invoke this file" — no code path
  # in the sweep is supposed to create it.
  cat > "$FX/adapters/claude-code/hooks/zz-prose-only.sh" <<EOF
#!/bin/bash
# Usage: zz-prose-only.sh --self-test   (documented, never implemented)
touch "$TMPROOT/PROSE_WAS_RUN"
exit 0
EOF
  chmod +x "$FX/adapters/claude-code/hooks/zz-prose-only.sh"
  OUT="$(RUN --per-script-timeout 2 --tsv 2>&1)"
  if printf '%s' "$OUT" | grep -q 'zz-prose-only'; then
    _f "R7 prose-only-script-not-discovered" "it appeared in the report: $OUT"
  elif [ -f "$TMPROOT/PROSE_WAS_RUN" ]; then
    _f "R7 prose-only-script-not-executed" "the sweep RAN a script that only documents --self-test"
  else
    _p "R7 prose-only-script-neither-discovered-nor-executed"
  fi

  # R8 — garbage bounds must never become "unbounded".
  OUT="$(RUN --per-script-timeout abc --total-budget xyz --only aa-pass --tsv 2>&1)"
  if printf '%s' "$OUT" | grep -q '^PASS	hooks/aa-pass.sh'; then _p "R8 garbage-bounds-normalized"; else _f "R8 garbage-bounds-normalized" "$OUT"; fi

  printf '\nself-test summary: %s passed, %s failed\n' "$PASSED" "$FAILED" >&2
  [ "$FAILED" -eq 0 ] || exit 1
  exit 0
fi

_sw_main
exit $?
