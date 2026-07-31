#!/bin/bash
# git-command-parse.sh — THE harness's single commit-target resolver.
#
# ============================================================================
# WHY THIS FILE EXISTS (class-level fix, 2026-07-29)
# ============================================================================
# harness-reviewer REJECTED review-record-commit-gate.sh FOUR times. Each round
# the builder fixed the shapes the reviewer demonstrated and shipped the CLASS.
#
# Round 3 diagnosed the class as "two hand-rolled parsers that disagree" and
# mandated ONE resolver. What round 3 actually shipped was one shared TOKENIZER
# and TWO different SPLITTERS — scope-enforcement-gate.sh kept its own
# quote-blind `sed -e 's/&&/\n/g' -e 's/;/\n/g'`. The gates still disagreed.
#
# Round-4 verdict, verbatim: "Delegation closed every shape I named and shipped
# the class for a fourth round, plus three new classes. The root cause is that
# the verification corpus is still my list. The fix that would actually break
# the pattern is a GENERATED cross-product over {prefix} x {cd-form} x
# {target-form} x {quoting} x {separator} in --self-test, plus a cross-gate
# agreement test, rather than another enumeration of instances."
#
# ROUND 5 IS THAT FIX. The self-test's primary artifact is no longer a list of
# instances a reviewer happened to name; it is a GENERATOR (Group 9) that
# enumerates 11,760 commands from five orthogonal dimensions and checks each
# against an ORACLE (`_gcp_gen_expect`) that derives the answer from shell
# semantics WITHOUT EVER CONSULTING THIS PARSER. The generator found the shapes
# round 4 named, and more besides — see GENERATOR-FOUND below.
#
# scope-enforcement-gate.sh now calls `gcp_resolve_commit_target` wholesale. It
# is not "the same tokenizer"; it is the same function. Group 10 is a standing
# cross-gate agreement test that feeds one corpus to both gates and asserts
# their commit-detection and target-resolution match.
#
# ============================================================================
# PUBLIC API
# ============================================================================
# Primitives (extracted verbatim from scope-enforcement-gate.sh in round 3)
#
#   gcp_expand_tilde <path>                 -> stdout: leading ~ / ~/ expanded
#   gcp_is_abs_path <path>                  -> rc 0 if POSIX-absolute or Windows
#                                              drive-letter absolute
#   gcp_compose_dir <cur> <base> <p>        -> stdout: absolute <p> wins; else
#                                              <p> resolved against <cur>; else
#                                              against <base>
#   gcp_tokenize_segment <segment>          -> populates GCP_SEG_TOKENS[]
#                                              (quote-aware: '' and "" stripped,
#                                              whitespace splits outside quotes)
#   gcp_analyze_git_segment <segment> <base>
#         sets GCP_SEG_IS_COMMIT   1 iff the subcommand token is exactly `commit`
#                                  (commit-tree / commit-graph excluded)
#              GCP_SEG_C_TARGET    composed `-C` target, "" when absent.
#              GCP_SEG_WORK_TREE   composed `--work-tree` target, "" when absent
#              GCP_SEG_GIT_DIR     composed `--git-dir` target, "" when absent
#
#   gcp_parse_cd_target <segment> <base>    -> stdout: resolved `cd` target
#   gcp_parse_cd_target_var <segment> <base>-> same, into GCP_CD_TARGET, NO FORK
#
# Composed helpers
#
#   gcp_strip_command_prefix_var <segment>  -> GCP_STRIPPED with leading shell
#                                              grouping/keyword tokens removed
#                                              ( { ! time then do else elif
#                                              while until, and trailing ) } ).
#   gcp_is_cd_segment <segment>             -> rc 0 for cd / pushd / Set-Location
#   gcp_strip_env_assignments_var <segment> -> GCP_STRIPPED with leading
#                                              VAR=value prefixes removed,
#                                              QUOTE-AWARE. Also populates
#                                              GCP_ASSIGN_NAMES/VALUES.
#   gcp_strip_env_assignments <segment>     -> stdout wrapper (API compat)
#   gcp_split_command <command>             -> populates GCP_SEGMENTS[] by
#                                              splitting on && || ; | & and
#                                              newline OUTSIDE quotes, treating
#                                              here-doc bodies as OPAQUE.
#
#   gcp_resolve_commit_target <command> <cwd>
#         sets GCP_IS_COMMIT      1 iff a `git commit` appears in COMMAND
#                                 POSITION anywhere in the command
#              GCP_TARGET_DIR     the directory the commit targets, or "" for
#                                 "the caller's cwd". Priority: --work-tree >
#                                 --git-dir (trailing /.git stripped) > -C >
#                                 accumulated cd/pushd > "".
#              GCP_PARSE_DEGRADED 1 if a guard tripped and the parse is not
#                                 trustworthy.
#
# ============================================================================
# BAILOUTS RESOLVE TOWARD DETECTION, NEVER TOWARD SILENCE
# ============================================================================
# Every guard here, when it trips, leaves GCP_PARSE_DEGRADED=1 and lets the
# caller decide — it never quietly reports "not a commit". Callers that gate on
# this MUST treat GCP_PARSE_DEGRADED=1 as "assume it is a commit and check".
#
# ROUND-5 CRITICAL C2: that principle was DEAD CODE. The resolver called
# `seg="$(gcp_strip_env_assignments "$seg")"` — a COMMAND SUBSTITUTION, i.e. a
# subshell. `GCP_PARSE_DEGRADED=1` was set in the child and discarded on exit.
# PROVEN: direct call -> 1; via $( ) -> 0. The principle above, the consumer
# branch in review-record-commit-gate.sh, and the manifest's "all three bailouts
# resolve toward BLOCK" were ALL unreachable. Every hot-path helper now has a
# `_var` form that writes a named global and is called WITHOUT a subshell; the
# stdout forms remain only as API-compat wrappers. Group 11 asserts the global
# is visible after the REAL call-site invocation form, which is the only form
# that could have caught this.
#
# ============================================================================
# COMMAND POSITION IS NOT "THE SEGMENT STARTS WITH git" (ROUND-5 CRITICAL C3)
# ============================================================================
# It was. So `( cd H && git commit )`, `(git commit)`, `{ ...; }`,
# `if true; then git commit; fi`, `for f in a; do git commit; done`,
# `! git commit`, `time git commit`, and `git \<newline> commit` were ALL
# fail-open. `( cd X && git <verb> )` occurs 210 times in adapters/ on this tree, and
# work-integrity-gate.sh:1093 is literally that shape. Leading grouping and
# keyword tokens are now stripped (gcp_strip_command_prefix_var) before the
# position test, in BOTH the git test and gcp_is_cd_segment; backslash-newline
# line continuations are removed by the splitter, as a shell does.
#
# ============================================================================
# ENV-ASSIGNMENT STRIPPING IS TOKEN-BASED, NOT REGEX (ROUND-5 CRITICAL C1)
# ============================================================================
# The old stripper used a quote-BLIND regex, so
#   REVIEW_RECORD_GATE_OVERRIDE="production is down and this cannot wait" git commit
# desynced the parse and the resolver returned not-a-commit. The gate's own
# block message printed, verbatim, the one shape that bypassed it — and a SHORT
# reason (no spaces) was correctly rejected and blocked, so the validation was
# INVERTED: the more substantive the waiver, the more silently it bypassed. Same
# defect broke `GIT_AUTHOR_NAME="A B" git commit` and `EDITOR="code -w" git commit`.
# The stripper is now a quote-aware word scanner sharing the tokenizer's rules.
#
# ============================================================================
# PERFORMANCE (ROUND-5 CRITICAL C5)
# ============================================================================
# `gcp_split_command` was a per-character bash loop over the WHOLE command, run
# before any commit test, on EVERY Bash tool call. `${s:i:1}` is O(i) in bash,
# so the loop was QUADRATIC. Measured in-process on this tree, bash 5.3:
#   1KB 67ms | 8KB 482ms | 32KB 4851ms | 64KB 15920ms | 100KB 37567ms
# Three fixes, in order of effect:
#   1. PRE-FILTER: no `commit` substring -> return immediately via a builtin
#      `case`. This is the 99% case and costs one pattern match.
#   2. JUMP-SCAN: the splitter now jumps metacharacter-to-metacharacter with
#      `${rest%%[<meta>]*}` instead of stepping character-by-character.
#   3. HARD CAP: above GCP_MAX_CMD_LEN (default 65536) the splitter refuses to
#      run and sets GCP_PARSE_DEGRADED=1 — which resolves toward DETECTION, per
#      the principle above, rather than looping.
# KNOWN, INHERITED GAP: the pre-filter is substring-based, so an obfuscated verb
# (`git co""mmit`) skips the gate. This is the SAME documented skip
# scope-enforcement-gate.sh has carried since its own pre-filter landed (its
# self-test scenario 34, "obfuscated-verb-prefilter-gap"). Naming it here so the
# two gates' known gaps stay identical rather than drifting apart.
#
# ============================================================================
# GENERATOR-FOUND (defects the round-4 brief did NOT list; Group 9 found these)
# ============================================================================
#   G1. `cd "/a b" && git commit` — a QUOTED cd target combined with a leading
#       `(`/`{`/keyword was mis-parsed even after the prefix fix, because
#       gcp_is_cd_segment pattern-matched the RAW segment. Both the cd test and
#       the cd PARSE now run on the prefix-stripped text.
#   G2. `echo 'x' && git commit` — an escaped single quote produced by the
#       generator's own `'\''` quoting exposed that the splitter's in-single-
#       quote state ignored the shell rule that `\` is NOT special inside single
#       quotes but IS special immediately after the closing quote. Pinned.
#   G3. Trailing `)` / `}` on the commit segment (`git commit -m x )`) left a
#       junk token that a future `-C`-style flag walk would consume as a value.
#       Trailing group closers are now stripped.
#   G4. `git --git-dir X --work-tree Y commit` in SEPARATED form with a
#       relative Y composed against the wrong base when a `cd` preceded it in
#       the same command.
#   G5. Here-doc bodies were split as commands, so `cat >> f <<EOF\ngit commit\nEOF`
#       resolved IS_COMMIT=1 — a pure over-fire on documentation writes. Bodies
#       are now opaque (this is round-4 M2, but the generator found it
#       independently across all 10 prefix x 6 separator combinations).
#
# ============================================================================
# PORTABILITY
# ============================================================================
# Must run on bash 3.2.57 (/bin/bash on macOS) and bash 5.x. Consequences:
#   - NEVER expand "${arr[@]}" on a possibly-empty array: under `set -u` bash 3.2
#     raises "unbound variable". Always index with ${#arr[@]} + for ((i=0;i<n;i++)).
#   - No associative arrays, no ${var^^}, no mapfile, no `declare -A`.
# Sourced by scripts both with and without `set -u`, so every read of a
# possibly-unset variable uses ${VAR:-}.
#
# Self-test: bash git-command-parse.sh --self-test
# ============================================================================

# Metacharacter class for the splitter's jump-scan. Built once, via $'...', so
# the backslash is a LITERAL backslash inside the bracket expression rather than
# an escape for the character after it. Group 12 pins its membership — get this
# class wrong and the splitter silently stops splitting.
_GCP_META=$'[\\\\\'"&|;\n<]'

# Commands longer than this are not parsed; the resolver sets
# GCP_PARSE_DEGRADED=1 instead (resolves toward DETECTION, never silence).
: "${GCP_MAX_CMD_LEN:=65536}"

# ------------------------------------------------------------------
# Primitives — lifted verbatim from scope-enforcement-gate.sh (round 3)
# ------------------------------------------------------------------

# Expand a leading ~ / ~/ to $HOME.
gcp_expand_tilde() {
  local p="$1"
  case "$p" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${p#\~/}" ;;
    *) printf '%s' "$p" ;;
  esac
}

# Is $1 an absolute path (POSIX or Windows drive-letter)?
gcp_is_abs_path() {
  case "$1" in
    /*) return 0 ;;
    [A-Za-z]:/*|[A-Za-z]:\\*) return 0 ;;
    *) return 1 ;;
  esac
}

# Compose a directory path: absolute $3 wins; else resolve $3 against the
# accumulated target $1; else against the base $2 (git's effective cwd).
gcp_compose_dir() {
  local cur="$1" base="$2" p="$3"
  p=$(gcp_expand_tilde "$p")
  if gcp_is_abs_path "$p"; then
    printf '%s' "$p"
  elif [[ -n "$cur" ]]; then
    printf '%s/%s' "$cur" "$p"
  elif [[ -n "$base" ]]; then
    printf '%s/%s' "$base" "$p"
  else
    printf '%s' "$p"
  fi
}

# Tokenize a command segment respecting single/double quotes.
# Populates global array GCP_SEG_TOKENS.
gcp_tokenize_segment() {
  local s="$1" i ch n cur="" in_dq=0 in_sq=0 have=0
  GCP_SEG_TOKENS=()
  n=${#s}
  for ((i=0; i<n; i++)); do
    ch="${s:i:1}"
    if [[ $in_sq -eq 1 ]]; then
      if [[ "$ch" == "'" ]]; then in_sq=0; else cur+="$ch"; fi
      continue
    fi
    if [[ $in_dq -eq 1 ]]; then
      if [[ "$ch" == '"' ]]; then in_dq=0; else cur+="$ch"; fi
      continue
    fi
    case "$ch" in
      "'") in_sq=1; have=1 ;;
      '"') in_dq=1; have=1 ;;
      ' '|$'\t')
        if [[ -n "$cur" ]] || [[ $have -eq 1 ]]; then
          GCP_SEG_TOKENS+=("$cur"); cur=""; have=0
        fi
        ;;
      *) cur+="$ch"; have=1 ;;
    esac
  done
  if [[ -n "$cur" ]] || [[ $have -eq 1 ]]; then
    GCP_SEG_TOKENS+=("$cur")
  fi
}

# Analyze a `git …` segment. See PUBLIC API above for the globals it sets.
gcp_analyze_git_segment() {
  local seg="$1" base="$2"
  GCP_SEG_IS_COMMIT=0
  GCP_SEG_C_TARGET=""
  GCP_SEG_WORK_TREE=""
  GCP_SEG_GIT_DIR=""
  gcp_tokenize_segment "$seg"
  local n=${#GCP_SEG_TOKENS[@]} i tok
  [[ $n -ge 2 ]] || return 0
  [[ "${GCP_SEG_TOKENS[0]}" == "git" ]] || return 0
  for ((i=1; i<n; i++)); do
    tok="${GCP_SEG_TOKENS[$i]}"
    case "$tok" in
      -C)
        i=$((i+1))
        [[ $i -lt $n ]] || break
        GCP_SEG_C_TARGET=$(gcp_compose_dir "$GCP_SEG_C_TARGET" "$base" "${GCP_SEG_TOKENS[$i]}")
        ;;
      -C?*)
        GCP_SEG_C_TARGET=$(gcp_compose_dir "$GCP_SEG_C_TARGET" "$base" "${tok:2}")
        ;;
      # --work-tree / --git-dir, GLUED form (`--work-tree=/path`). The reference
      # implementation let these fall through to the generic `-*` arm and dropped
      # them, so `git --git-dir=X/.git --work-tree=X commit` resolved to the
      # process cwd — a PROVEN fail-open for the review-record gate (probe C4).
      --work-tree=?*)
        GCP_SEG_WORK_TREE=$(gcp_compose_dir "" "$base" "${tok#--work-tree=}")
        ;;
      --git-dir=?*)
        GCP_SEG_GIT_DIR=$(gcp_compose_dir "" "$base" "${tok#--git-dir=}")
        ;;
      # Separated form (`--work-tree /path`).
      --work-tree)
        i=$((i+1))
        [[ $i -lt $n ]] || break
        GCP_SEG_WORK_TREE=$(gcp_compose_dir "" "$base" "${GCP_SEG_TOKENS[$i]}")
        ;;
      --git-dir)
        i=$((i+1))
        [[ $i -lt $n ]] || break
        GCP_SEG_GIT_DIR=$(gcp_compose_dir "" "$base" "${GCP_SEG_TOKENS[$i]}")
        ;;
      --namespace|-c)
        i=$((i+1))   # global flags whose value is a separate token
        ;;
      -*)
        :            # other global flags (boolean, or value glued with =)
        ;;
      *)
        if [[ "$tok" == "commit" ]]; then
          GCP_SEG_IS_COMMIT=1
        fi
        return 0
        ;;
    esac
  done
  return 0
}

# Parse a `cd <path>` / `pushd <path>` / `Set-Location <path>` segment into
# GCP_CD_TARGET. Relative paths resolve against $2. Bare `cd` -> $HOME.
# NO SUBSHELL — see the C2 banner. The stdout form below wraps this.
gcp_parse_cd_target_var() {
  local seg="$1" base="$2"
  gcp_strip_command_prefix_var "$seg"
  gcp_tokenize_segment "$GCP_STRIPPED"
  local n=${#GCP_SEG_TOKENS[@]}
  if [[ $n -lt 2 ]]; then
    GCP_CD_TARGET="$HOME"
    return 0
  fi
  local p="${GCP_SEG_TOKENS[1]}"
  # Skip a leading flag (cd -P/-L, Set-Location -LiteralPath/-Path)
  if [[ "$p" == -* ]] && [[ $n -ge 3 ]]; then
    p="${GCP_SEG_TOKENS[2]}"
  fi
  p=$(gcp_expand_tilde "$p")
  if gcp_is_abs_path "$p"; then
    GCP_CD_TARGET="$p"
  elif [[ -n "$base" ]]; then
    GCP_CD_TARGET="$base/$p"
  else
    GCP_CD_TARGET="$p"
  fi
  return 0
}

gcp_parse_cd_target() {
  gcp_parse_cd_target_var "$1" "${2:-}"
  printf '%s' "$GCP_CD_TARGET"
}

# ------------------------------------------------------------------
# Composed helpers — the single resolver
# ------------------------------------------------------------------

# Strip leading shell grouping and keyword tokens, and trailing group closers,
# so the command-position test sees the actual command word.
#
# ROUND-5 C3. Command position used to be "the segment starts with the literal
# string git", which fail-opened on eleven shapes. Stripping is deliberately
# limited to a FIXED keyword set — anything else (bash, sh, eval, echo, grep)
# is left alone, so `bash -c 'git commit'` and `echo "git commit"` stay
# non-commits. That is what keeps this a detection fix and not an over-fire.
gcp_strip_command_prefix_var() {
  local s="$1" prev=""
  # FAST BAIL: the overwhelmingly common segment is a plain command word plus
  # arguments — no grouping character, no leading keyword, no trailing closer,
  # already trimmed by the caller. Profiled at 65ms of a 220ms resolve over a
  # 32KB separator-dense command; this returns it to a single pattern match.
  case "$s" in
    [A-Za-z0-9_/.-]*)
      case "$s" in
        time|time[[:space:]]*|then|then[[:space:]]*|do|do[[:space:]]*|\
        else|else[[:space:]]*|elif|elif[[:space:]]*|while|while[[:space:]]*|\
        until|until[[:space:]]*|if|if[[:space:]]*) ;;
        *')'|*'}'|*';'|*[[:space:]]) ;;
        *) GCP_STRIPPED="$s"; return 0 ;;
      esac
      ;;
  esac
  # trim
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    # Leading grouping characters, which need no following whitespace: `(cd x`
    # is valid shell, so `(` must be stripped even when glued to the command.
    while :; do
      case "$s" in
        '('*|'{'*) s="${s#?}" ;;
        *) break ;;
      esac
      s="${s#"${s%%[![:space:]]*}"}"
    done
    # Leading keyword WORDS, which do require a whitespace boundary.
    case "$s" in
      '!'|'!'[[:space:]]*) s="${s#?}" ;;
      time|time[[:space:]]*) s="${s#time}" ;;
      then|then[[:space:]]*) s="${s#then}" ;;
      do|do[[:space:]]*) s="${s#do}" ;;
      else|else[[:space:]]*) s="${s#else}" ;;
      elif|elif[[:space:]]*) s="${s#elif}" ;;
      while|while[[:space:]]*) s="${s#while}" ;;
      until|until[[:space:]]*) s="${s#until}" ;;
      if|if[[:space:]]*) s="${s#if}" ;;
    esac
    s="${s#"${s%%[![:space:]]*}"}"
  done
  # Trailing group closers and terminators (`git commit -m x )`). Left in place
  # these become junk tokens that a flag walk can consume as a value (G3).
  prev=""
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    case "$s" in
      *')'|*'}'|*';') s="${s%?}" ;;
    esac
    s="${s%"${s##*[![:space:]]}"}"
  done
  GCP_STRIPPED="$s"
  return 0
}

# Does this segment change the working directory to a NAMED target?
# `cd` with no argument means $HOME and counts. Bare `pushd` / `popd` rotate a
# stack we cannot model, so they are deliberately NOT matched.
#
# ROUND-5 C3/G1: this pattern-matched the RAW segment, so `( cd H` and
# `then cd H` were not cd segments and the accumulated target stayed empty —
# the commit then resolved to the process cwd. It now tests the prefix-stripped
# text, the same text the git-position test sees.
gcp_is_cd_segment() {
  gcp_strip_command_prefix_var "$1"
  case "$GCP_STRIPPED" in
    cd|cd[[:space:]]*) return 0 ;;
    pushd[[:space:]]*) return 0 ;;
    [Ss]et-[Ll]ocation|[Ss]et-[Ll]ocation[[:space:]]*) return 0 ;;
  esac
  return 1
}

# Strip leading `VAR=value` assignments from a segment, QUOTE-AWARE (C1).
# Sets GCP_STRIPPED, and records the assignments it consumed into
# GCP_ASSIGN_NAMES[] / GCP_ASSIGN_VALUES[] (used for M1 inline-variable
# substitution). NO SUBSHELL — GCP_PARSE_DEGRADED must reach the caller (C2).
gcp_strip_env_assignments_var() {
  local s="$1" n i ch guard=0
  GCP_ASSIGN_NAMES=(); GCP_ASSIGN_VALUES=()
  s="${s#"${s%%[![:space:]]*}"}"
  # FAST BAIL: an assignment prefix REQUIRES an `=`. Without one anywhere in the
  # segment there is nothing to strip, and we skip the character walk entirely.
  # Profiled on a 32KB separator-dense command (842 segments): this walk was
  # 78ms of a 220ms resolve. Safe by construction — no `=`, no assignment.
  case "$s" in
    *=*) : ;;
    *) GCP_STRIPPED="$s"; return 0 ;;
  esac
  n=${#s}
  i=0
  while [[ $i -lt $n ]]; do
    # Scan ONE word, quote-aware, building both its raw extent and its dequoted
    # value. The old regex did neither, which is precisely why a quoted value
    # containing spaces desynced the parse.
    local start=$i deq="" in_sq=0 in_dq=0 done_word=0
    while [[ $i -lt $n ]]; do
      ch="${s:i:1}"
      if [[ $in_sq -eq 1 ]]; then
        if [[ "$ch" == "'" ]]; then in_sq=0; else deq+="$ch"; fi
        i=$((i+1)); continue
      fi
      if [[ $in_dq -eq 1 ]]; then
        if [[ "$ch" == '"' ]]; then in_dq=0
        elif [[ "$ch" == '\' ]] && [[ $((i+1)) -lt $n ]]; then
          i=$((i+1)); deq+="${s:i:1}"
        else deq+="$ch"; fi
        i=$((i+1)); continue
      fi
      case "$ch" in
        "'") in_sq=1 ;;
        '"') in_dq=1 ;;
        '\')
          if [[ $((i+1)) -lt $n ]]; then i=$((i+1)); deq+="${s:i:1}"; else deq+="$ch"; fi
          ;;
        ' '|$'\t') done_word=1 ;;
        *) deq+="$ch" ;;
      esac
      [[ $done_word -eq 1 ]] && break
      i=$((i+1))
    done
    # Not an assignment -> the real command starts at $start. Stop.
    case "$deq" in
      [A-Za-z_]*=*)
        case "${deq%%=*}" in
          *[!A-Za-z0-9_]*) i=$start; break ;;
        esac
        ;;
      *) i=$start; break ;;
    esac
    GCP_ASSIGN_NAMES+=("${deq%%=*}")
    GCP_ASSIGN_VALUES+=("${deq#*=}")
    # Consume the run of whitespace after the assignment.
    while [[ $i -lt $n ]]; do
      case "${s:i:1}" in
        ' '|$'\t') i=$((i+1)) ;;
        *) break ;;
      esac
    done
    guard=$((guard+1))
    if [[ $guard -gt 256 ]]; then
      # Guard tripped: the parse is no longer trustworthy. Say so rather than
      # returning a clean-looking result the caller will treat as authoritative.
      GCP_PARSE_DEGRADED=1
      break
    fi
  done
  GCP_STRIPPED="${s:i}"
  return 0
}

# API-compat stdout wrapper. NOT used on the hot path — a command substitution
# would discard GCP_PARSE_DEGRADED, which is the exact defect C2 names.
gcp_strip_env_assignments() {
  gcp_strip_env_assignments_var "$1"
  printf '%s' "$GCP_STRIPPED"
}

# Substitute inline shell-variable assignments seen EARLIER in the same command
# into $1, longest name first. Sets GCP_SUBSTITUTED.
#
# ROUND-5 M1. `W=/other/repo; git -C "$W" commit` used to resolve to the literal
# `<cwd>/$W`, which does not exist, so review-record-commit-gate fell back to the
# cwd and BLOCKED a commit aimed at an unrelated repo over whatever harness file
# happened to be staged. Tracking the assignment resolves it to /other/repo and
# the gate correctly declines. Crucially this does NOT reopen the round-3
# fail-open for `git -C $REPO commit` with no visible assignment: that target
# still contains an unresolved `$`, which the gate treats as "unknown, check
# anyway".
gcp_subst_vars_var() {
  local s="$1" n i j tmp
  GCP_SUBSTITUTED="$s"
  n=${#GCP_VAR_NAMES[@]}
  [[ $n -gt 0 ]] || return 0
  # longest-name-first so $FOO does not eat the head of $FOOBAR
  local -a ord=()
  for ((i=0; i<n; i++)); do ord+=("$i"); done
  for ((i=1; i<n; i++)); do
    for ((j=0; j<n-i; j++)); do
      if [[ ${#GCP_VAR_NAMES[${ord[$j]}]} -lt ${#GCP_VAR_NAMES[${ord[$((j+1))]}]} ]]; then
        tmp="${ord[$j]}"; ord[$j]="${ord[$((j+1))]}"; ord[$((j+1))]="$tmp"
      fi
    done
  done
  for ((i=0; i<n; i++)); do
    local nm="${GCP_VAR_NAMES[${ord[$i]}]}" vl="${GCP_VAR_VALUES[${ord[$i]}]}"
    GCP_SUBSTITUTED="${GCP_SUBSTITUTED//\$\{$nm\}/$vl}"
    GCP_SUBSTITUTED="${GCP_SUBSTITUTED//\$$nm/$vl}"
  done
  return 0
}

# Look up a command-scoped env assignment captured from the commit segment by
# gcp_resolve_commit_target. Sets GCP_ENV_VALUE (empty when absent) and returns
# 0 iff the name was present.
gcp_commit_env_value() {
  local want="$1" i n
  GCP_ENV_VALUE=""
  n=${#GCP_COMMIT_ENV_NAMES[@]}
  for ((i=0; i<n; i++)); do
    if [[ "${GCP_COMMIT_ENV_NAMES[$i]}" == "$want" ]]; then
      GCP_ENV_VALUE="${GCP_COMMIT_ENV_VALUES[$i]}"
      return 0
    fi
  done
  return 1
}

# Split a command into segments on && || ; | & and newline, OUTSIDE quotes.
# Populates GCP_SEGMENTS[]. Quotes and every other character are preserved
# verbatim so gcp_tokenize_segment can do its own quote handling downstream.
#
# ROUND-5: jump-scan instead of per-character stepping (C5), backslash-newline
# line continuations removed as a shell does (C3), and here-doc bodies kept
# OPAQUE (M2/G5) so `cat >> f <<EOF\ngit commit\nEOF` is a documentation write,
# not a commit.
gcp_split_command() {
  local s="$1"
  GCP_SEGMENTS=()

  # FAST PATH (round 5). The jump-scan below costs O(length) per METACHARACTER,
  # so a separator-dense command is still slow: an end-to-end measurement of
  # scope-enforcement-gate over a 32KB `echo … && `-dense payload containing the
  # word `commit` went 66ms -> 1051ms when that gate moved onto this splitter,
  # because its old `sed` splitter was external and linear. That is a real
  # regression and it is fixed here rather than hidden behind the length cap.
  #
  # The insight: quote-awareness only matters if there are quotes. With no `'`,
  # no `"`, no `\` and no `<` anywhere, there is nothing that can protect a
  # separator, so naive substitution is EXACTLY equivalent — and it is six
  # linear builtin passes instead of a per-metacharacter walk. Group 18 asserts
  # the two paths agree segment-for-segment; GCP_FORCE_SLOW_SPLIT=1 disables
  # this path so the comparison is real.
  if [[ "${GCP_FORCE_SLOW_SPLIT:-0}" != "1" ]]; then
    case "$s" in
      *\'*|*\"*|*\\*|*'<'*) : ;;   # quoting or a here-doc — must use the scan
      *)
        # An empty command has no metacharacters either, but `read -a` yields a
        # ZERO-length array where the scan yields one empty segment. Group 18
        # caught that as a real disagreement.
        if [[ -z "$s" ]]; then GCP_SEGMENTS=(""); return 0; fi
        # NEWLINE is the sentinel, and a `read` loop does the splitting.
        #
        # PORTABILITY, TWICE OVER — both found by the generator, neither by
        # reading the code. (1) A version using a bracket class ($'[;|&\n]') to
        # sweep the single-character separators in one pass works on bash 5.3
        # and matches NOTHING on bash 3.2. (2) A version using $'\001' as the
        # field separator with `read -a` works on bash 5.3 and, on bash 3.2,
        # silently STRIPS the \001 bytes without splitting at all — via the IFS
        # prefix form, the explicit-IFS form, AND word splitting. Either bug
        # returned the whole command as ONE segment, so every cd/commit pair
        # fail-opened: 1536 of 11760 cells red. Newline is the one delimiter both
        # interpreters agree on, and a `read` loop (unlike word splitting)
        # preserves empty fields. Literal patterns only; two-character operators
        # first, so a leftover `&` really is a single `&`.
        local fast="$s" _seg
        if [[ ${#s} -gt 2048 ]] && command -v tr >/dev/null 2>&1; then
          # ${var//pat/rep} is itself QUADRATIC on bash 3.2. Measured split time
          # for a separator-dense payload there: 4KB 30ms, 8KB 78ms, 16KB 469ms,
          # 32KB 2984ms — so the builtin passes reintroduce, on the stock macOS
          # interpreter, exactly the cost this path exists to remove. One `tr` is
          # linear and costs a single fork, and the fork is only ever paid by a
          # command that already passed the `*commit*` pre-filter. `&&` and `||`
          # become two newlines and therefore an empty segment between them;
          # empty segments are skipped by every caller, which is why Group 18
          # compares NON-EMPTY segments.
          fast="$(printf '%s' "$s" | tr ';|&' '\n\n\n')"
        else
          fast="${fast//&&/$'\n'}"
          fast="${fast//||/$'\n'}"
          fast="${fast//;/$'\n'}"
          fast="${fast//|/$'\n'}"
          fast="${fast//&/$'\n'}"
        fi
        while IFS= read -r _seg; do GCP_SEGMENTS+=("$_seg"); done <<< "$fast"
        return 0 ;;
    esac
  fi

  local cur="" rest="$s" head ch nx delim raw hd_pending=0
  while [[ -n "$rest" ]]; do
    # Jump straight to the next metacharacter; everything before it is inert.
    head="${rest%%$_GCP_META*}"
    if [[ "$head" == "$rest" ]]; then
      cur+="$rest"; rest=""; break
    fi
    cur+="$head"
    rest="${rest:${#head}}"
    ch="${rest:0:1}"
    case "$ch" in
      "'")
        # Single quotes: NOTHING is special inside, not even backslash.
        rest="${rest:1}"; cur+="'"
        head="${rest%%\'*}"
        if [[ "$head" == "$rest" ]]; then cur+="$rest"; rest=""    # unterminated
        else cur+="$head'"; rest="${rest:$((${#head}+1))}"; fi
        ;;
      '"')
        # Double quotes: backslash escapes the next character, so an escaped
        # quote must not end the string early.
        rest="${rest:1}"; cur+='"'
        while [[ -n "$rest" ]]; do
          head="${rest%%[\\\"]*}"
          if [[ "$head" == "$rest" ]]; then cur+="$rest"; rest=""; break; fi
          cur+="$head"; rest="${rest:${#head}}"
          if [[ "${rest:0:1}" == '"' ]]; then cur+='"'; rest="${rest:1}"; break; fi
          cur+="${rest:0:2}"; rest="${rest:2}"        # backslash + escapee
        done
        ;;
      '\')
        nx="${rest:1:1}"
        if [[ "$nx" == $'\n' ]]; then
          rest="${rest:2}"                            # line continuation: gone
        elif [[ -n "$nx" ]]; then
          cur+="${rest:0:2}"; rest="${rest:2}"
        else
          cur+="$ch"; rest="${rest:1}"
        fi
        ;;
      '<')
        nx="${rest:1:1}"
        if [[ "$nx" == '<' ]] && [[ "${rest:2:1}" != '<' ]]; then
          # here-doc: `<<`, `<<-`, delimiter optionally quoted
          raw="${rest:0:2}"; rest="${rest:2}"
          if [[ "${rest:0:1}" == '-' ]]; then raw+="-"; rest="${rest:1}"; fi
          while [[ "${rest:0:1}" == ' ' || "${rest:0:1}" == $'\t' ]]; do
            raw+="${rest:0:1}"; rest="${rest:1}"
          done
          delim=""
          while [[ -n "$rest" ]]; do
            ch="${rest:0:1}"
            case "$ch" in
              ' '|$'\t'|$'\n'|';'|'&'|'|'|')') break ;;
              "'"|'"'|'\') raw+="$ch"; rest="${rest:1}" ;;
              *) delim+="$ch"; raw+="$ch"; rest="${rest:1}" ;;
            esac
          done
          cur+="$raw"
          [[ -n "$delim" ]] && hd_pending=1
        else
          cur+="$ch"; rest="${rest:1}"
        fi
        ;;
      '&'|'|')
        rest="${rest:1}"
        [[ "${rest:0:1}" == "$ch" ]] && rest="${rest:1}"   # second char of && / ||
        GCP_SEGMENTS+=("$cur"); cur=""
        ;;
      ';')
        rest="${rest:1}"
        GCP_SEGMENTS+=("$cur"); cur=""
        ;;
      $'\n')
        rest="${rest:1}"
        if [[ $hd_pending -eq 1 ]]; then
          # Everything up to the terminator line is here-doc BODY: data, not
          # commands. Append it verbatim and never split it.
          hd_pending=0
          cur+=$'\n'
          if [[ "$rest" == "$delim"$'\n'* ]]; then
            cur+="$delim"; rest="${rest:$((${#delim}+1))}"
            GCP_SEGMENTS+=("$cur"); cur=""     # the terminator's newline separates
          elif [[ "$rest" == *$'\n'"$delim"$'\n'* ]]; then
            head="${rest%%$'\n'"$delim"$'\n'*}"
            cur+="$head"$'\n'"$delim"
            rest="${rest:$((${#head}+${#delim}+2))}"
            GCP_SEGMENTS+=("$cur"); cur=""     # ...so a command AFTER the
                                               # here-doc is its own segment (G6)
          elif [[ "$rest" == "$delim" ]] || [[ "$rest" == *$'\n'"$delim" ]]; then
            cur+="$rest"; rest=""
          else
            cur+="$rest"; rest=""                    # unterminated -> all body
          fi
        else
          GCP_SEGMENTS+=("$cur"); cur=""
        fi
        ;;
      *) cur+="$ch"; rest="${rest:1}" ;;
    esac
  done
  GCP_SEGMENTS+=("$cur")
}

# Resolve whether a command commits, and which directory it commits in.
# See PUBLIC API above for the globals it sets.
gcp_resolve_commit_target() {
  local cmd="$1" cwd="${2:-}"
  GCP_IS_COMMIT=0
  GCP_TARGET_DIR=""
  GCP_PARSE_DEGRADED=0
  GCP_VAR_NAMES=(); GCP_VAR_VALUES=()
  GCP_COMMIT_ENV_NAMES=(); GCP_COMMIT_ENV_VALUES=()

  # C5 PRE-FILTER. `git commit` cannot appear without the substring `commit`,
  # and this runs on EVERY Bash tool call. One builtin pattern match instead of
  # a quadratic character walk. See the PERFORMANCE banner for the known
  # obfuscated-verb gap this shares with scope-enforcement-gate.sh.
  case "$cmd" in
    *commit*) : ;;
    *) return 0 ;;
  esac

  # C5 HARD CAP. Resolves toward DETECTION: the caller sees DEGRADED, not a
  # confident "not a commit".
  if [[ ${#cmd} -gt ${GCP_MAX_CMD_LEN:-65536} ]]; then
    GCP_PARSE_DEGRADED=1
    return 0
  fi

  gcp_split_command "$cmd"
  local n=${#GCP_SEGMENTS[@]} i j m seg cd_target="" base
  for ((i=0; i<n; i++)); do
    seg="${GCP_SEGMENTS[$i]}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg%"${seg##*[![:space:]]}"}"
    [[ -n "$seg" ]] || continue

    # DIRECT CALL, NOT $( ) — GCP_PARSE_DEGRADED must survive (C2).
    gcp_strip_env_assignments_var "$seg"
    seg="$GCP_STRIPPED"
    if [[ -z "$seg" ]]; then
      # The whole segment was assignments, so these are SHELL variables that
      # persist for the rest of the command (`W=/x; git -C "$W" commit`), not
      # command-scoped env (`FOO=bar git commit`). Only the former get recorded.
      m=${#GCP_ASSIGN_NAMES[@]}
      for ((j=0; j<m; j++)); do
        GCP_VAR_NAMES+=("${GCP_ASSIGN_NAMES[$j]}")
        GCP_VAR_VALUES+=("${GCP_ASSIGN_VALUES[$j]}")
      done
      continue
    fi
    if [[ ${#GCP_VAR_NAMES[@]} -gt 0 ]]; then
      gcp_subst_vars_var "$seg"; seg="$GCP_SUBSTITUTED"
    fi

    base="$cd_target"
    [[ -n "$base" ]] || base="$cwd"

    if gcp_is_cd_segment "$seg"; then
      gcp_parse_cd_target_var "$seg" "$base"
      cd_target="$GCP_CD_TARGET"
      continue
    fi

    # COMMAND POSITION, not "starts with git" (C3).
    gcp_strip_command_prefix_var "$seg"
    case "$GCP_STRIPPED" in
      git|git[[:space:]]*) ;;
      *) continue ;;
    esac
    gcp_analyze_git_segment "$GCP_STRIPPED" "$base"
    if [[ "${GCP_SEG_IS_COMMIT:-0}" -eq 1 ]]; then
      GCP_IS_COMMIT=1
      # COMMAND-SCOPED env on the commit itself (`FOO=bar git commit`). A
      # PreToolUse hook runs BEFORE the shell that would apply this assignment,
      # so the hook's own environment never contains it — a gate that reads only
      # getenv() can never see an inline waiver. Exposed here so callers can.
      m=${#GCP_ASSIGN_NAMES[@]}
      for ((j=0; j<m; j++)); do
        GCP_COMMIT_ENV_NAMES+=("${GCP_ASSIGN_NAMES[$j]}")
        GCP_COMMIT_ENV_VALUES+=("${GCP_ASSIGN_VALUES[$j]}")
      done
      if [[ -n "${GCP_SEG_WORK_TREE:-}" ]]; then
        GCP_TARGET_DIR="$GCP_SEG_WORK_TREE"
      elif [[ -n "${GCP_SEG_GIT_DIR:-}" ]]; then
        GCP_TARGET_DIR="${GCP_SEG_GIT_DIR%/.git}"
      elif [[ -n "${GCP_SEG_C_TARGET:-}" ]]; then
        GCP_TARGET_DIR="$GCP_SEG_C_TARGET"
      elif [[ -n "$cd_target" ]]; then
        GCP_TARGET_DIR="$cd_target"
      fi
      return 0
    fi
  done
  return 0
}

# Milliseconds since epoch, without GNU date and without a `timeout` dependency.
_gcp_ms() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local e="${EPOCHREALTIME/,/.}"
    printf '%s' "$(( ${e%%.*} * 1000 + 10#${e#*.} / 1000 ))"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time;print(int(time.time()*1000))'
  else
    printf '%s' "$(( $(date +%s) * 1000 ))"
  fi
}

# ===========================================================================
# Self-test
# ===========================================================================
# Groups 1-8 are the ROUND-3 suite, kept verbatim: they are the pre-existing
# oracle for the extraction and must not be weakened.
# Group 9 is the ROUND-5 GENERATOR — the actual deliverable. See its banner.
# ===========================================================================
_gcp_self_test() {
  local PASS=0 FAIL=0
  _p() { PASS=$((PASS+1)); echo "  PASS: $*"; }
  _f() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }

  # eq <label> <expected> <actual>
  _eq() {
    if [[ "$2" == "$3" ]]; then _p "$1"; else _f "$1 (expected '$2', got '$3')"; fi
  }
  # resolve <cmd> <cwd> -> "<is_commit>|<target>"
  _r() {
    gcp_resolve_commit_target "$1" "$2"
    printf '%s|%s' "$GCP_IS_COMMIT" "$GCP_TARGET_DIR"
  }
  local V; V="$(printf 'com''mit')"

  echo "Group 1: tokenizer respects quotes"
  gcp_tokenize_segment 'git -C "/a b/c" commit -m "x y"'
  _eq "quoted path is ONE token with quotes stripped" "/a b/c" "${GCP_SEG_TOKENS[2]}"
  _eq "token count" "6" "${#GCP_SEG_TOKENS[@]}"
  gcp_tokenize_segment "git -C '/s q/r' commit"
  _eq "single-quoted path is one token" "/s q/r" "${GCP_SEG_TOKENS[2]}"
  gcp_tokenize_segment ''
  _eq "empty segment -> zero tokens" "0" "${#GCP_SEG_TOKENS[@]}"

  echo "Group 2: path helpers"
  _eq "tilde expands"        "$HOME/x"  "$(gcp_expand_tilde '~/x')"
  _eq "bare tilde expands"   "$HOME"    "$(gcp_expand_tilde '~')"
  gcp_is_abs_path "/a"     && _p "POSIX absolute detected"      || _f "POSIX absolute missed"
  gcp_is_abs_path "C:/a"   && _p "Windows drive-letter absolute" || _f "Windows drive-letter missed"
  gcp_is_abs_path "rel/a"  && _f "relative wrongly absolute"     || _p "relative not absolute"
  _eq "absolute wins over base"     "/abs"     "$(gcp_compose_dir '' '/base' '/abs')"
  _eq "relative resolves vs cur"    "/cur/r"   "$(gcp_compose_dir '/cur' '/base' 'r')"
  _eq "relative resolves vs base"   "/base/r"  "$(gcp_compose_dir '' '/base' 'r')"

  echo "Group 3: git segment analysis"
  gcp_analyze_git_segment "git $V -m x" "/base"
  _eq "plain commit detected"       "1"  "$GCP_SEG_IS_COMMIT"
  _eq "no -C target"                ""   "$GCP_SEG_C_TARGET"
  gcp_analyze_git_segment "git -C /t $V" "/base"
  _eq "-C separated captured"       "/t" "$GCP_SEG_C_TARGET"
  gcp_analyze_git_segment "git -C/t $V" "/base"
  _eq "-C glued captured"           "/t" "$GCP_SEG_C_TARGET"
  gcp_analyze_git_segment "git -C \"/q p\" $V" "/base"
  _eq "-C quoted path captured"     "/q p" "$GCP_SEG_C_TARGET"
  gcp_analyze_git_segment "git -C rel $V" "/base"
  _eq "-C relative resolves vs base" "/base/rel" "$GCP_SEG_C_TARGET"
  gcp_analyze_git_segment "git -C /a -C b $V" "/base"
  _eq "repeated -C composes"        "/a/b" "$GCP_SEG_C_TARGET"
  gcp_analyze_git_segment "git ${V}-tree x" "/base"
  _eq "commit-tree is NOT commit"   "0"  "$GCP_SEG_IS_COMMIT"
  gcp_analyze_git_segment "git ${V}-graph write" "/base"
  _eq "commit-graph is NOT commit"  "0"  "$GCP_SEG_IS_COMMIT"
  gcp_analyze_git_segment "git status" "/base"
  _eq "status is not commit"        "0"  "$GCP_SEG_IS_COMMIT"
  gcp_analyze_git_segment "git --work-tree=/w --git-dir=/w/.git $V" "/base"
  _eq "glued --work-tree captured"  "/w" "$GCP_SEG_WORK_TREE"
  _eq "glued --git-dir captured"    "/w/.git" "$GCP_SEG_GIT_DIR"
  _eq "and it is still a commit"    "1"  "$GCP_SEG_IS_COMMIT"
  gcp_analyze_git_segment "git --work-tree /w2 $V" "/base"
  _eq "separated --work-tree captured" "/w2" "$GCP_SEG_WORK_TREE"
  gcp_analyze_git_segment "git -c user.name=x $V" "/base"
  _eq "-c value skipped, commit found" "1" "$GCP_SEG_IS_COMMIT"

  echo "Group 4: cd parsing"
  _eq "cd absolute"        "/t"        "$(gcp_parse_cd_target 'cd /t' '/base')"
  _eq "cd relative"        "/base/sub" "$(gcp_parse_cd_target 'cd sub' '/base')"
  _eq "cd quoted"          "/a b"      "$(gcp_parse_cd_target 'cd "/a b"' '/base')"
  _eq "cd tilde"           "$HOME/p"   "$(gcp_parse_cd_target 'cd ~/p' '/base')"
  _eq "bare cd -> HOME"    "$HOME"     "$(gcp_parse_cd_target 'cd' '/base')"
  _eq "cd -P flag skipped" "/t"        "$(gcp_parse_cd_target 'cd -P /t' '/base')"
  gcp_is_cd_segment 'cd /x'        && _p "cd is a cd segment"       || _f "cd missed"
  gcp_is_cd_segment 'pushd /x'     && _p "pushd is a cd segment"    || _f "pushd missed"
  gcp_is_cd_segment 'Set-Location /x' && _p "Set-Location is a cd segment" || _f "Set-Location missed"
  gcp_is_cd_segment 'pushd'        && _f "bare pushd wrongly matched" || _p "bare pushd not matched (stack unmodelled)"
  gcp_is_cd_segment 'cdrom x'      && _f "cdrom wrongly matched"    || _p "cdrom is not cd"

  echo "Group 5: quote-aware splitting (the over-fire fix)"
  gcp_split_command 'a && b ; c || d | e'
  _eq "splits on all separators" "5" "${#GCP_SEGMENTS[@]}"
  gcp_split_command 'echo "x ; y && z"'
  _eq "separators INSIDE double quotes do not split" "1" "${#GCP_SEGMENTS[@]}"
  gcp_split_command "echo 'x ; y'"
  _eq "separators INSIDE single quotes do not split" "1" "${#GCP_SEGMENTS[@]}"
  gcp_split_command 'echo \; still-one'
  _eq "escaped separator does not split" "1" "${#GCP_SEGMENTS[@]}"

  echo "Group 6: end-to-end resolution — MUST detect"
  _eq "plain commit"            "1|"        "$(_r "git $V -m x" /cwd)"
  _eq "-C quoted"               "1|/r p"    "$(_r "git -C \"/r p\" $V -m x" /cwd)"
  _eq "-C single-quoted"        "1|/r p"    "$(_r "git -C '/r p' $V -m x" /cwd)"
  _eq "cd then commit"          "1|/tgt"    "$(_r "cd /tgt && git $V -m x" /cwd)"
  _eq "pushd then commit"       "1|/tgt"    "$(_r "pushd /tgt && git $V -m x" /cwd)"
  _eq "cd ; commit"             "1|/tgt"    "$(_r "cd /tgt; git $V -m x" /cwd)"
  _eq "--git-dir/--work-tree"   "1|/tgt"    "$(_r "git --git-dir=/tgt/.git --work-tree=/tgt $V -m x" /cwd)"
  _eq "--git-dir alone strips /.git" "1|/tgt" "$(_r "git --git-dir=/tgt/.git $V -m x" /cwd)"
  _eq "env assignment prefix"   "1|"        "$(_r "FOO=bar git $V -m x" /cwd)"
  _eq "env assignment TAB"      "1|"        "$(_r "FOO=bar$(printf '\t')git $V -m x" /cwd)"
  _eq "chained relative cds"    "1|/a/b/c"  "$(_r "cd /a/b && cd c && git $V -m x" /cwd)"
  _eq "unexpanded var -C kept literal" "1|/cwd/\$REPO" "$(_r "git -C \$REPO $V -m x" /cwd)"

  echo "Group 7: end-to-end resolution — MUST NOT detect"
  _eq "mention in echo"      "0|" "$(_r "echo run git $V later" /cwd)"
  _eq "man page"             "0|" "$(_r "man git $V" /cwd)"
  _eq "grep for the phrase"  "0|" "$(_r "grep -rn 'git $V' docs/" /cwd)"
  _eq "separator inside a quoted string" "0|" "$(_r "echo \"step: stage; git $V -m msg\" >> notes.md" /cwd)"
  _eq "commit as a message word" "0|" "$(_r "echo 'please git $V soon'" /cwd)"
  _eq "git status only"      "0|" "$(_r "git status" /cwd)"
  _eq "commit-tree"          "0|" "$(_r "git ${V}-tree deadbeef" /cwd)"

  echo "Group 8: only the COMMIT segment contributes its target"
  _eq "earlier -C must not leak" "1|" "$(_r "git -C /elsewhere log --oneline -1 && git add -A && git $V -m x" /cwd)"
  _eq "-C inside a commit MESSAGE must not leak" "1|" "$(_r "git $V -m 'use git -C /other next time'" /cwd)"
  _eq "-C in an echoed string must not leak" "1|" "$(_r "echo \"git -C /other status\" && git $V -m x" /cwd)"

  # =========================================================================
  echo "Group 9: GENERATED CROSS-PRODUCT (round-5 primary deliverable)"
  # =========================================================================
  # Round 4's verdict was that the verification corpus was still the REVIEWER'S
  # LIST — so each round closed the named instances and shipped the class. This
  # group replaces the list with a GENERATOR over five orthogonal dimensions:
  #
  #   {prefix} x {cd-form} x {target-form} x {quoting} x {separator}
  #
  # Two functions drive it, and they are deliberately INDEPENDENT:
  #   _gcp_gen_build  assembles the command STRING from the dimension indices
  #   _gcp_gen_expect derives the EXPECTED verdict from the same indices, by
  #                   reasoning about what a real shell does — it never calls
  #                   this parser. That independence is the whole point: an
  #                   oracle that consults the implementation cannot fail.
  #
  # DETECTION CONTRACT (the rule the oracle encodes): GCP_IS_COMMIT is 1 iff a
  # `git commit` appears in COMMAND POSITION, regardless of whether control flow
  # would actually reach it. `false || git commit` and `if true; then git commit;
  # fi` are both 1. Conditional execution is not the gate's business; potential
  # execution is. This is the fail-safe reading.
  #
  # GENUINELY AMBIGUOUS CELLS — named, and resolved toward DETECTION:
  #   (a) target-form `var` ($REPO with no visible assignment). A real shell
  #       expands it; a static parser cannot. Fail-safe = keep the literal so
  #       the target is visibly unresolvable, and STILL report the commit. The
  #       caller then treats an unresolved `$` as "unknown, check anyway".
  #   (b) target-form `spaces` (an UNQUOTED path containing a space). This is a
  #       broken command: `git -C /tgt repo commit` makes `repo` the subcommand,
  #       so it does not commit at all. Where a `cd` form leaves the commit
  #       intact the target is unassertable, so those cells assert IS_COMMIT
  #       ONLY (counted and reported separately, never silently skipped).
  #   (c) cd-form `--git-dir=~/x` (glued) with target-form `tilde`. bash does
  #       NOT tilde-expand after `=` in a non-assignment word, so a real git
  #       would receive a literal `~`. We expand anyway, uniformly, because a
  #       resolvable path the caller can check beats an unresolvable one.
  _gcp_run_generator
  if [[ $GEN_FAIL -eq 0 ]]; then _p "generated cross-product: $GEN_N/$GEN_N"
  else _f "generated cross-product: $GEN_FAIL of $GEN_N combinations wrong"; fi

  echo "Group 10: C2 — GCP_PARSE_DEGRADED survives the REAL call-site form"
  # The round-4 defect was not that the guard was missing; it was that the guard
  # set a global inside a $( ) subshell, so no caller ever saw it. Asserting the
  # helper in isolation is exactly the test that stayed green through four
  # rounds. These assert the global AFTER the resolver call, which is the only
  # invocation form any consumer actually uses.
  local BIGENV="" k
  for ((k=0; k<300; k++)); do BIGENV+="V$k=x "; done
  gcp_resolve_commit_target "${BIGENV}git $V -m x" /cwd
  _eq "300 env assignments trip the guard THROUGH the resolver" "1" "$GCP_PARSE_DEGRADED"
  gcp_resolve_commit_target "git $V -m x" /cwd
  _eq "a clean parse leaves DEGRADED clear" "0" "$GCP_PARSE_DEGRADED"
  local LONGCMD; LONGCMD="echo $(printf '%*s' 70000 '' | tr ' ' 'a') && git $V -m x"
  gcp_resolve_commit_target "$LONGCMD" /cwd
  _eq "over-cap command sets DEGRADED, not a confident not-a-commit" "1" "$GCP_PARSE_DEGRADED"
  _eq "over-cap command does NOT claim not-a-commit silently" "0" "$GCP_IS_COMMIT"
  # 40 assignments must now PARSE, not degrade — the old guard was 32.
  local ENV40=""; for ((k=0; k<40; k++)); do ENV40+="V$k=x "; done
  _eq "40 env assignments resolve cleanly" "1|" "$(_r "${ENV40}git $V -m x" /cwd)"

  echo "Group 11: C5 — pre-filter and cap keep the hot path flat"
  local BIG; BIG="$(printf '%*s' 102400 '' | tr ' ' 'a')"
  local t0 t1
  # UNDER-CAP, NO `commit` SUBSTRING — this is the assertion that actually pins
  # the PRE-FILTER. A deletion mutation of the pre-filter left the whole suite
  # green until this was added, because the 100KB cases below are caught by the
  # length cap instead, and the cap masked the missing pre-filter. 60KB sits
  # below GCP_MAX_CMD_LEN, so only the pre-filter can make this fast.
  #
  # The payload must be SEPARATOR-DENSE. A first version of this test padded
  # with plain 'a's and still passed under the mutation: with no metacharacter
  # anywhere, the jump-scan finds none and returns in one step, so it was fast
  # for a reason that had nothing to do with the pre-filter. Real commands are
  # separator-dense; this one is too.
  local UNDERCAP=""
  while [[ ${#UNDERCAP} -lt 60000 ]]; do UNDERCAP+="echo aaaaaaaaaaaaaaaaaaaa && "; done
  t0=$(_gcp_ms)
  gcp_resolve_commit_target "$UNDERCAP" /cwd
  t1=$(_gcp_ms)
  if [[ $((t1-t0)) -lt 200 ]]; then _p "60KB under-cap command with no commit substring: $((t1-t0))ms (<200ms)"
  else _f "60KB under-cap no-commit command took $((t1-t0))ms — the pre-filter is not firing"; fi
  _eq "...and is correctly not a commit" "0" "$GCP_IS_COMMIT"
  _eq "...and is NOT degraded (it was parsed, not given up on)" "0" "$GCP_PARSE_DEGRADED"
  t0=$(_gcp_ms)
  gcp_resolve_commit_target "echo $BIG" /cwd
  t1=$(_gcp_ms)
  if [[ $((t1-t0)) -lt 200 ]]; then _p "100KB command with no commit substring: $((t1-t0))ms (<200ms)"
  else _f "100KB no-commit command took $((t1-t0))ms, must be <200ms"; fi
  _eq "...and is not a commit" "0" "$GCP_IS_COMMIT"
  t0=$(_gcp_ms)
  gcp_resolve_commit_target "echo $BIG && git $V -m x" /cwd
  t1=$(_gcp_ms)
  if [[ $((t1-t0)) -lt 200 ]]; then _p "100KB command CONTAINING commit: $((t1-t0))ms (<200ms)"
  else _f "100KB commit command took $((t1-t0))ms, must be <200ms"; fi
  _eq "...and resolves toward detection via DEGRADED" "1" "$GCP_PARSE_DEGRADED"

  echo "Group 12: the splitter's metacharacter class"
  # _GCP_META is built with $'...' so its backslash is literal. Get that wrong
  # and the splitter silently stops splitting — every gate fail-opens at once,
  # with a green suite. Pin the class by behaviour, one metacharacter at a time.
  local mc
  for mc in '&' '|' ';'; do
    gcp_split_command "a ${mc} b"
    _eq "single '${mc}' splits into 2" "2" "${#GCP_SEGMENTS[@]}"
  done
  gcp_split_command "a"$'\n'"b"
  _eq "newline splits into 2" "2" "${#GCP_SEGMENTS[@]}"
  gcp_split_command 'a "b;c" d'
  _eq "double quote suppresses the split" "1" "${#GCP_SEGMENTS[@]}"
  gcp_split_command "a 'b;c' d"
  _eq "single quote suppresses the split" "1" "${#GCP_SEGMENTS[@]}"
  gcp_split_command 'a \; b'
  _eq "backslash suppresses the split" "1" "${#GCP_SEGMENTS[@]}"
  gcp_split_command "cat <<EOF"$'\n'"a; b"$'\n'"EOF"
  _eq "here-doc body is opaque" "1" "${#GCP_SEGMENTS[@]}"

  echo "Group 13: M1 — inline variable assignments resolve the target"
  _eq "assigned var resolves to the real repo" "1|/other/repo" \
      "$(_r "W=/other/repo; git -C \"\$W\" $V -m x" /cwd)"
  _eq "braced form resolves too" "1|/other/repo" \
      "$(_r "W=/other/repo; git -C \"\${W}\" $V -m x" /cwd)"
  _eq "assigned var via cd" "1|/other/repo" \
      "$(_r "W=/other/repo; cd \"\$W\" && git $V -m x" /cwd)"
  # The round-3 fail-open must NOT reopen: with no visible assignment the target
  # stays literal, so the caller still sees an unresolved '$' and checks anyway.
  _eq "UNassigned var stays literal (round-3 fail-open stays closed)" "1|/cwd/\$REPO" \
      "$(_r "git -C \$REPO $V -m x" /cwd)"
  # command-scoped env (`FOO=bar git ...`) must NOT become a shell variable
  _eq "command-scoped env does not leak into later segments" "1|/cwd/\$W" \
      "$(_r "W=/other/repo git status; git -C \$W $V -m x" /cwd)"
  # G3: a group closer GLUED to the cd target. Without trailing-closer stripping
  # the target becomes the literal `/tgt)`. The generated corpus is BLIND to
  # this (it only emits spaced closers), so it is pinned here explicitly.
  _eq "glued group closer does not corrupt the cd target" "1|/tgt" \
      "$(_r "( cd /tgt) && git $V -m x" /cwd)"

  echo "Group 14: M2 — here-doc bodies and -c/--eval arguments are OPAQUE"
  _eq "here-doc body is not a command"      "0|" "$(_r "cat >> f <<EOF"$'\n'"git $V -m x"$'\n'"EOF" /cwd)"
  _eq "quoted-delimiter here-doc"           "0|" "$(_r "cat >> f <<'EOF'"$'\n'"git $V -m x"$'\n'"EOF" /cwd)"
  _eq "tab-stripped here-doc (<<-)"         "0|" "$(_r "cat >> f <<-EOF"$'\n'"git $V -m x"$'\n'"EOF" /cwd)"
  _eq "bash -c argument"                    "0|" "$(_r "bash -c 'git $V -m x'" /cwd)"
  _eq "bash -c with separators inside"      "0|" "$(_r "bash -c \"cd /x && git $V -m x\"" /cwd)"
  _eq "perl --eval style argument"          "0|" "$(_r "perl --eval 'git $V -m x'" /cwd)"
  # ...but a command AFTER the here-doc still counts.
  _eq "commit after a here-doc still detected" "1|" \
      "$(_r "cat >> f <<EOF"$'\n'"notes"$'\n'"EOF"$'\n'"git $V -m x" /cwd)"

  echo "Group 15: C1 — the waiver syntax the block message prints must PARSE"
  # The gate's own block message tells the operator to run
  #   REVIEW_RECORD_GATE_OVERRIDE="why this cannot wait" git commit ...
  # Under the quote-blind stripper that exact shape resolved not-a-commit, so
  # the gate never ran and the waiver was never logged: a SILENT UNLOGGED
  # bypass, printed verbatim in the block message. Worse, a SHORT reason (no
  # spaces) parsed fine and blocked — the validation was inverted.
  _eq "long quoted waiver reason IS a commit" "1|" \
      "$(_r "REVIEW_RECORD_GATE_OVERRIDE=\"production is down and this cannot wait\" git $V -m x" /cwd)"
  _eq "short unquoted waiver reason IS a commit (unchanged)" "1|" \
      "$(_r "REVIEW_RECORD_GATE_OVERRIDE=short git $V -m x" /cwd)"
  _eq "GIT_AUTHOR_NAME with a space" "1|" "$(_r "GIT_AUTHOR_NAME=\"A B\" git $V -m x" /cwd)"
  _eq "EDITOR with flags"            "1|" "$(_r "EDITOR=\"code -w\" git $V -m x" /cwd)"
  _eq "single-quoted env value"      "1|" "$(_r "MSG='a b c' git $V -m x" /cwd)"
  _eq "env value with an = inside"   "1|" "$(_r "OPTS=\"a=b c=d\" git $V -m x" /cwd)"
  _eq "quoted env then -C"           "1|/r p" \
      "$(_r "EDITOR=\"code -w\" git -C \"/r p\" $V -m x" /cwd)"

  echo "Group 18: the splitter's FAST PATH agrees with the scan, segment for segment"
  # The fast path is only sound because a command with no quote, backslash or
  # here-doc character has nothing that could protect a separator. Assert that
  # equivalence directly instead of trusting the argument: run every quote-free
  # shape down BOTH paths and compare.
  local -a FP=()
  FP+=("git $V -m x")
  FP+=("cd /tgt && git $V -m x")
  FP+=("cd /tgt; git $V -m x")
  FP+=("a && b ; c || d | e")
  FP+=("a & b")
  FP+=("echo lead"$'\n'"git $V -m x")
  FP+=("git -C /tgt $V -m x")
  FP+=("for f in a; do git $V -m x; done")
  FP+=("if true; then git $V -m x; fi")
  FP+=("( cd /tgt && git $V -m x )")
  FP+=("a &&")
  FP+=("a ;; b")
  FP+=("")
  FP+=("|")
  FP+=("echo run git $V later")
  # NON-EMPTY segments are the meaningful comparison: the large-input `tr` pass
  # turns `&&` into two newlines and so emits an empty segment between them,
  # which every caller skips. Comparing raw arrays would fail on a difference
  # that cannot change any verdict.
  local fi_ fn_=${#FP[@]} FDIFF=0 slow_dump fast_dump k_
  for ((fi_=0; fi_<fn_; fi_++)); do
    GCP_FORCE_SLOW_SPLIT=1 gcp_split_command "${FP[$fi_]}"
    slow_dump=""
    for ((k_=0; k_<${#GCP_SEGMENTS[@]}; k_++)); do
      [[ -n "${GCP_SEGMENTS[$k_]// /}" ]] && slow_dump+="<${GCP_SEGMENTS[$k_]}>"
    done
    GCP_FORCE_SLOW_SPLIT=0 gcp_split_command "${FP[$fi_]}"
    fast_dump=""
    for ((k_=0; k_<${#GCP_SEGMENTS[@]}; k_++)); do
      [[ -n "${GCP_SEGMENTS[$k_]// /}" ]] && fast_dump+="<${GCP_SEGMENTS[$k_]}>"
    done
    if [[ "$slow_dump" != "$fast_dump" ]]; then
      FDIFF=$((FDIFF+1))
      echo "  DIFF on '$(printf '%s' "${FP[$fi_]}" | tr '\n' '~')'"
      echo "        scan: $slow_dump"
      echo "        fast: $fast_dump"
    fi
  done
  if [[ $FDIFF -eq 0 ]]; then _p "fast/scan split agreement: $fn_/$fn_ shapes identical"
  else _f "fast/scan split DISAGREE on $FDIFF of $fn_ shapes"; fi
  # And the fast path must actually be taken — otherwise this group is vacuous.
  local t0f t1f DENSE=""
  while [[ ${#DENSE} -lt 32768 ]]; do DENSE+="echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa && "; done
  t0f=$(_gcp_ms); gcp_resolve_commit_target "$DENSE git $V -m x" /cwd; t1f=$(_gcp_ms)
  if [[ $((t1f-t0f)) -lt 200 ]]; then _p "32KB separator-dense commit resolves in $((t1f-t0f))ms (<200ms)"
  else _f "32KB separator-dense commit took $((t1f-t0f))ms — the fast path is not being taken"; fi
  _eq "...and is still correctly detected" "1" "$GCP_IS_COMMIT"

  echo "Group 17: the GENERATOR's own escapers are interpreter-independent"
  # A corpus is only as trustworthy as the strings it builds. These escapers
  # were written with ${var//pat/rep} and silently produced DIFFERENT output on
  # bash 3.2 than on 5.x, so the bash-3.2 run scored 180 malformed commands and
  # blamed the parser. Assert the exact bytes, so a regression is a test
  # failure rather than a phantom parser bug.
  _eq "esc_sq wraps a quote as '\\''"  "a'\\''b"     "$(_gcp_gen_esc_sq "a'b")"
  _eq "esc_sq leaves quoteless text"   "abc"         "$(_gcp_gen_esc_sq "abc")"
  _eq "esc_dq escapes a double quote"  'a\"b'        "$(_gcp_gen_esc_dq 'a"b')"
  _eq "esc_dq escapes a backslash"     'a\\b'        "$(_gcp_gen_esc_dq 'a\b')"
  _eq "esc_dq escapes a dollar"        'a\$b'        "$(_gcp_gen_esc_dq 'a$b')"
  _eq "esc_dq escapes a backtick"      'a\`b'        "$(_gcp_gen_esc_dq 'a`b')"

  echo "Group 16: CROSS-GATE AGREEMENT — both gates must resolve identically"
  # Round 3's mandate was "ONE commit-target resolver instead of two that
  # disagree". It shipped one shared TOKENIZER and TWO SPLITTERS, and the gates
  # kept disagreeing. Two PROVEN pairs from the round-4 review are the first two
  # entries below. This test feeds ONE corpus to BOTH gates and asserts their
  # commit-detection AND target-resolution match.
  #
  # Each gate is asked via SCOPE_PRINT_TARGET=1, which prints the conclusion the
  # gate's OWN code path reached. Calling the lib directly from here would pass
  # even if a gate went back to rolling its own splitter — the exact round-4
  # failure — so this deliberately goes through the gates as processes.
  local _GDIR; _GDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
  local SG="$_GDIR/scope-enforcement-gate.sh" RG="$_GDIR/review-record-commit-gate.sh"
  if [[ ! -f "$SG" ]] || [[ ! -f "$RG" ]] || ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: gates or jq not present (lib is being tested standalone)"
  else
    local -a XC=()
    XC+=("echo \"stage; git $V -m msg\" >> notes.md")   # PROVEN pair 1: scope over-fired
    XC+=("pushd /tmp && git $V -m x")                   # PROVEN pair 2: scope failed open
    XC+=("git $V -m x")
    XC+=("git -C \"/r p\" $V -m x")
    XC+=("git -C '/r p' $V -m x")
    XC+=("cd /tgt && git $V -m x")
    XC+=("cd /tgt; git $V -m x")
    XC+=("git --git-dir=/tgt/.git --work-tree=/tgt $V -m x")
    XC+=("( cd /tgt && git $V -m x )")
    XC+=("(git $V -m x)")
    XC+=("{ cd /tgt && git $V -m x; }")
    XC+=("if true; then git $V -m x; fi")
    XC+=("for f in a; do git $V -m x; done")
    XC+=("! git $V -m x")
    XC+=("time git $V -m x")
    XC+=("REVIEW_RECORD_GATE_OVERRIDE=\"production is down and this cannot wait\" git $V -m x")
    XC+=("GIT_AUTHOR_NAME=\"A B\" git $V -m x")
    XC+=("W=/other/repo; git -C \"\$W\" $V -m x")
    XC+=("git -C \$REPO $V -m x")
    XC+=("cat >> f <<EOF"$'\n'"git $V -m x"$'\n'"EOF")
    XC+=("bash -c 'git $V -m x'")
    XC+=("echo run git $V later")
    XC+=("git status")
    XC+=("git ${V}-tree deadbeef")
    XC+=("grep -rn 'git $V' docs/")
    XC+=("git -C /elsewhere log --oneline -1 && git add -A && git $V -m x")
    XC+=("git \\"$'\n'"$V -m x")
    XC+=("cd /a/b && cd c && git $V -m x")
    local xi xn=${#XC[@]} payload a b XFAIL=0
    for ((xi=0; xi<xn; xi++)); do
      payload="$(jq -nc --arg c "${XC[$xi]}" '{tool_name:"Bash",tool_input:{command:$c}}')"
      a="$(printf '%s' "$payload" | SCOPE_PRINT_TARGET=1 bash "$SG" 2>/dev/null)"
      b="$(printf '%s' "$payload" | SCOPE_PRINT_TARGET=1 bash "$RG" 2>/dev/null)"
      if [[ "$a" != "$b" ]]; then
        XFAIL=$((XFAIL+1))
        echo "  DISAGREE: scope='$a' review-record='$b'"
        echo "            cmd $(printf '%s' "${XC[$xi]}" | tr '\n' '~')"
      fi
    done
    if [[ $XFAIL -eq 0 ]]; then _p "cross-gate agreement: $xn/$xn commands resolve identically"
    else _f "cross-gate agreement: $XFAIL of $xn commands DISAGREE"; fi
  fi

  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

# --- Group 9 generator: command builder and independent oracle ---------------
# Kept at file scope (not nested in _gcp_self_test) so bash 3.2 does not
# re-parse them on every one of the 11,760 iterations.

# raw target path per target-form
_gcp_gen_raw() {
  case "$1" in
    0) printf '/tgt/repo' ;;
    1) printf 'sub/dir' ;;
    2) printf '/tgt repo' ;;
    3) printf '/tgt repo' ;;
    4) printf '~/tgtrepo' ;;
    5) printf '$REPO' ;;
    6) printf '/no/such/dir' ;;
    7) printf '/tgt repo' ;;
  esac
}
# shell literal for a path, per target-form's quoting style
_gcp_gen_lit() {
  case "$1" in
    2) printf "'%s'" "$2" ;;
    3) printf '"%s"' "$2" ;;
    *) printf '%s' "$2" ;;
  esac
}
# Shell-literal escapers for the generator.
#
# PORTABILITY, THE HARD WAY: these were written as `${s//\'/\'\\\'\'}` and
# friends. bash 5.x and bash 3.2 do NOT agree on backslash processing in the
# REPLACEMENT half of ${var//pat/rep} — 5.3 produced `'\''` while 3.2 produced
# `\'\\'\'`. The corpus therefore generated 180 MALFORMED commands on bash 3.2,
# in which `&& git commit` really was outside quotes, and the parser correctly
# called them commits. The 180 "failures" were the GENERATOR's bug, not the
# parser's. Both escapers are now explicit character loops, whose behaviour is
# fixed at parse time by double-quote rules that the two interpreters DO agree
# on. Pinned by Group 17.
_gcp_gen_esc_sq() {
  local s="$1" out="" i n ch
  n=${#s}
  for ((i=0; i<n; i++)); do
    ch="${s:i:1}"
    if [[ "$ch" == "'" ]]; then out="$out'\\''"; else out="$out$ch"; fi
  done
  printf '%s' "$out"
}
_gcp_gen_esc_dq() {
  local s="$1" out="" i n ch
  n=${#s}
  for ((i=0; i<n; i++)); do
    ch="${s:i:1}"
    case "$ch" in
      '\'|'"'|'`'|'$') out="$out\\$ch" ;;
      *) out="$out$ch" ;;
    esac
  done
  printf '%s' "$out"
}

# _gcp_gen_build <d1> <d2> <d3> <d4> <d5> <verb> -> GEN_CMD
_gcp_gen_build() {
  local a="$1" b="$2" c="$3" q="$4" p="$5" vb="$6"
  local raw lit glit cdc flags bs inner
  raw="$(_gcp_gen_raw "$c")"
  lit="$(_gcp_gen_lit "$c" "$raw")"
  glit="$(_gcp_gen_lit "$c" "$raw/.git")"
  cdc=""; flags=""
  case "$b" in
    1) cdc="cd $lit && " ;;
    2) cdc="cd $lit; " ;;
    3) cdc="pushd $lit && " ;;
    4) flags="-C $lit" ;;
    5) flags="--git-dir=$glit --work-tree=$lit" ;;
    6) flags="--git-dir $glit --work-tree $lit" ;;
  esac
  if [[ "$a" == "9" ]]; then bs=" \\"$'\n'; else bs=" "; fi
  if [[ -n "$flags" ]]; then inner="git${bs}${flags}${bs}${vb} -m x"
  else inner="git${bs}${vb} -m x"; fi
  inner="${cdc}${inner}"
  case "$a" in
    1) inner="( $inner )" ;;
    2) inner="{ $inner; }" ;;
    3) inner="if true; then $inner; fi" ;;
    4) inner="for f in a; do $inner; done" ;;
    5) inner="! $inner" ;;
    6) inner="time $inner" ;;
    7) inner="FOO=bar $inner" ;;
    8) inner="GIT_AUTHOR_NAME=\"A B\" $inner" ;;
  esac
  case "$q" in
    1) inner="echo '$(_gcp_gen_esc_sq "$inner")' >> notes.md" ;;
    2) inner="echo \"$(_gcp_gen_esc_dq "$inner")\" >> notes.md" ;;
    3) inner="cat >> notes.md <<'EOF'"$'\n'"$inner"$'\n'"EOF" ;;
  esac
  case "$p" in
    1) inner="echo lead && $inner" ;;
    2) inner="false || $inner" ;;
    3) inner="echo lead; $inner" ;;
    4) inner="echo lead | $inner" ;;
    5) inner="echo lead"$'\n'"$inner" ;;
  esac
  GEN_CMD="$inner"
}

# Drive the whole cross-product. Sets GEN_N / GEN_PASS / GEN_FAIL / GEN_NA and
# the three ambiguity counters. Runnable on its own via `--self-test-generator`,
# which is how it gets MUTATION-VERIFIED: revert any one fix in this file and
# this corpus must go red, with the count naming how wide the class is.
_gcp_run_generator() {
  local d1 d2 d3 d4 d5 ok V
  V="$(printf 'com''mit')"
  GEN_N=0; GEN_PASS=0; GEN_FAIL=0; GEN_NA=0; GEN_SHOWN=0
  GEN_AMB_VAR=0; GEN_AMB_SPACE=0; GEN_AMB_TILDE=0
  for ((d1=0; d1<=9; d1++)); do
   for ((d2=0; d2<=6; d2++)); do
    for ((d3=0; d3<=7; d3++)); do
     # target-form is inapplicable when no cd-form names a target; running the
     # other seven would inflate the pass count with duplicates.
     if [[ $d2 -eq 0 ]] && [[ $d3 -ne 0 ]]; then GEN_NA=$((GEN_NA+1)); continue; fi
     for ((d4=0; d4<=3; d4++)); do
      for ((d5=0; d5<=5; d5++)); do
        _gcp_gen_build "$d1" "$d2" "$d3" "$d4" "$d5" "$V"
        _gcp_gen_expect "$d1" "$d2" "$d3" "$d4" "$d5"
        GEN_N=$((GEN_N+1))
        if [[ $d4 -eq 0 ]]; then
          [[ $d3 -eq 5 ]] && [[ $d2 -ne 0 ]] && GEN_AMB_VAR=$((GEN_AMB_VAR+1))
          [[ $d3 -eq 7 ]] && GEN_AMB_SPACE=$((GEN_AMB_SPACE+1))
          [[ $d3 -eq 4 ]] && [[ $d2 -eq 5 ]] && GEN_AMB_TILDE=$((GEN_AMB_TILDE+1))
        fi
        gcp_resolve_commit_target "$GEN_CMD" /cwd
        ok=1
        [[ "$GCP_IS_COMMIT" == "$EXP_IS" ]] || ok=0
        if [[ "$EXP_MODE" == "full" ]] && [[ "$GCP_TARGET_DIR" != "$EXP_TGT" ]]; then ok=0; fi
        if [[ $ok -eq 1 ]]; then
          GEN_PASS=$((GEN_PASS+1))
        else
          GEN_FAIL=$((GEN_FAIL+1))
          if [[ $GEN_SHOWN -lt 12 ]]; then
            GEN_SHOWN=$((GEN_SHOWN+1))
            echo "  FAIL[d1=$d1 d2=$d2 d3=$d3 d4=$d4 d5=$d5] expected IS=$EXP_IS TGT='$EXP_TGT' ($EXP_MODE)"
            echo "        got      IS=$GCP_IS_COMMIT TGT='$GCP_TARGET_DIR' DEG=$GCP_PARSE_DEGRADED"
            echo "        cmd      $(printf '%s' "$GEN_CMD" | tr '\n' '~')"
          fi
        fi
      done
     done
    done
   done
  done
  echo "  generated cross-product: $GEN_N combinations, $GEN_PASS pass, $GEN_FAIL fail"
  echo "    (skipped $GEN_NA as N/A: target-form is inapplicable when cd-form is 'none')"
  echo "    (ambiguous cells asserted toward DETECTION: $GEN_AMB_VAR unexpanded-var, $GEN_AMB_SPACE unquoted-space, $GEN_AMB_TILDE glued-tilde)"
  [[ $GEN_FAIL -eq 0 ]]
}

# THE ORACLE. Derives the verdict from shell semantics; never calls the parser.
# _gcp_gen_expect <d1> <d2> <d3> <d4> <d5> -> EXP_IS EXP_TGT EXP_MODE
_gcp_gen_expect() {
  local b="$2" c="$3" q="$4" raw
  EXP_MODE="full"
  # Quoted text and here-doc bodies are DATA. A shell never executes them.
  if [[ "$q" != "0" ]]; then EXP_IS=0; EXP_TGT=""; return 0; fi
  if [[ "$c" == "7" ]]; then
    case "$b" in
      4|5|6)
        # An unquoted space truncates the flag's value; the NEXT word becomes
        # git's subcommand, so this command does not commit at all.
        EXP_IS=0; EXP_TGT=""; return 0 ;;
      1|2|3)
        # `cd /tgt repo` is a runtime error, but `git commit` is still its own
        # command. Detectable; target unknowable.
        EXP_IS=1; EXP_TGT=""; EXP_MODE="is-only"; return 0 ;;
    esac
  fi
  EXP_IS=1
  if [[ "$b" == "0" ]]; then EXP_TGT=""; return 0; fi
  raw="$(_gcp_gen_raw "$c")"
  case "$raw" in
    /*)  EXP_TGT="$raw" ;;
    "~") EXP_TGT="$HOME" ;;
    "~/"*) EXP_TGT="$HOME/${raw#\~/}" ;;
    *)   EXP_TGT="/cwd/$raw" ;;
  esac
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) _gcp_self_test; exit $? ;;
    --self-test-generator) _gcp_run_generator; exit $? ;;
  esac
fi
