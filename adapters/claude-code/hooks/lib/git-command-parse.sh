#!/bin/bash
# git-command-parse.sh — THE harness's single commit-target resolver.
#
# ============================================================================
# WHY THIS FILE EXISTS (class-level fix, 2026-07-29)
# ============================================================================
# harness-reviewer REJECTED review-record-commit-gate.sh three times. Each round
# the builder fixed the one shape the reviewer demonstrated and shipped the CLASS
# intact. The class: two PreToolUse hooks in the SAME Bash dispatch chain each
# hand-rolled their own shell parsing, and they disagreed.
#
#   scope-enforcement-gate.sh  — quote-aware tokenizer, -C composition, cd
#                                tracking, tilde expansion (HARNESS-GAP-47,
#                                2026-06-10). Correct.
#   review-record-commit-gate.sh — `${rest//&&/...}` string surgery on the RAW
#                                command, a quote-blind segment walk, and a -C
#                                capture that took the FIRST bare token after
#                                `-C`. Fail-open on every quoted path.
#
# Round-3 reviewer verdict, verbatim: "stop hand-rolling shell parsing — extract
# those three functions to hooks/lib/ and source them, so the harness has ONE
# commit-target resolver instead of two that disagree."
#
# This file is that one resolver. The primitives below are LIFTED VERBATIM from
# scope-enforcement-gate.sh (_tokenize_segment / _analyze_git_segment /
# _parse_cd_target and their helpers) — that gate is the reference implementation
# and its behavior is the contract. Its 34-scenario self-test is the pre-existing
# oracle that proves the extraction changed nothing.
#
# ============================================================================
# PUBLIC API
# ============================================================================
# Primitives (extracted verbatim; scope-enforcement-gate.sh calls these directly)
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
#                                  Repeated -C composes per git semantics.
#              GCP_SEG_WORK_TREE   composed `--work-tree` target, "" when absent
#              GCP_SEG_GIT_DIR     composed `--git-dir` target, "" when absent
#         NOTE: WORK_TREE/GIT_DIR are ADDITIVE globals introduced for the
#         review-record gate. scope-enforcement-gate.sh reads only IS_COMMIT and
#         C_TARGET, so its behavior is unchanged by their presence — this is what
#         makes the extraction byte-equivalent for that gate.
#
#   gcp_parse_cd_target <segment> <base>    -> stdout: resolved `cd` target
#                                              (bare `cd` -> $HOME)
#
# Composed helpers (new; used by review-record-commit-gate.sh)
#
#   gcp_is_cd_segment <segment>             -> rc 0 for cd / pushd / Set-Location
#                                              WITH a target argument
#   gcp_strip_env_assignments <segment>     -> stdout: leading VAR=value prefixes
#                                              removed. Sets GCP_PARSE_DEGRADED=1
#                                              if the guard trips.
#   gcp_split_command <command>             -> populates GCP_SEGMENTS[] by
#                                              splitting on && || ; | & and
#                                              newline OUTSIDE quotes.
#                                              QUOTE-AWARE — this is the fix for
#                                              the over-fire where a separator
#                                              inside a quoted string
#                                              (`echo "stage; git commit"`)
#                                              manufactured a phantom command
#                                              segment.
#
#   gcp_resolve_commit_target <command> <cwd>
#         sets GCP_IS_COMMIT      1 iff a `git commit` appears in COMMAND
#                                 POSITION anywhere in the command
#              GCP_TARGET_DIR     the directory the commit actually targets, or
#                                 "" meaning "the caller's cwd". Priority:
#                                   1. --work-tree on the commit segment
#                                   2. --git-dir on the commit segment (with a
#                                      trailing /.git stripped)
#                                   3. -C composition on the commit segment
#                                   4. the accumulated cd/pushd target
#                                   5. "" (cwd)
#                                 Only the segment that actually matches `commit`
#                                 contributes its flags — a -C on an EARLIER
#                                 segment must never repoint the resolver.
#              GCP_PARSE_DEGRADED 1 if a guard tripped and the parse is not
#                                 trustworthy.
#
# ============================================================================
# BAILOUTS RESOLVE TOWARD DETECTION, NEVER TOWARD SILENCE
# ============================================================================
# Every guard in this file, when it trips, leaves GCP_PARSE_DEGRADED=1 and lets
# the caller decide — it never quietly reports "not a commit". A resolver whose
# failure mode is "authorizes everything" is worse than no resolver: the caller
# gets a confident rc=0 and no signal that parsing gave up. Callers that gate on
# this MUST treat GCP_PARSE_DEGRADED=1 as "assume it is a commit and check".
#
# ============================================================================
# PORTABILITY
# ============================================================================
# Must run on bash 3.2.57 (/bin/bash on macOS) and bash 5.x. Consequences:
#   - NEVER expand "${arr[@]}" on a possibly-empty array: under `set -u` bash 3.2
#     raises "unbound variable". Always index with ${#arr[@]} + for ((i=0;i<n;i++)).
#   - No associative arrays, no ${var^^}, no mapfile.
# Sourced by scripts both with and without `set -u`, so every read of a
# possibly-unset variable uses ${VAR:-}.
#
# Self-test: bash git-command-parse.sh --self-test
# ============================================================================

# ------------------------------------------------------------------
# Primitives — lifted verbatim from scope-enforcement-gate.sh
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
      # Captured into ADDITIVE globals so scope-enforcement-gate, which reads
      # neither, is byte-equivalent.
      --work-tree=?*)
        GCP_SEG_WORK_TREE=$(gcp_compose_dir "" "$base" "${tok#--work-tree=}")
        ;;
      --git-dir=?*)
        GCP_SEG_GIT_DIR=$(gcp_compose_dir "" "$base" "${tok#--git-dir=}")
        ;;
      # Separated form (`--work-tree /path`). The reference implementation
      # already skipped the value token; now it also records it.
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

# Parse a `cd <path>` / `pushd <path>` / `Set-Location <path>` segment; echo the
# resolved target (relative paths resolve against $2, the accumulated cd target
# or process cwd). Bare `cd` echoes $HOME.
gcp_parse_cd_target() {
  local seg="$1" base="$2"
  gcp_tokenize_segment "$seg"
  local n=${#GCP_SEG_TOKENS[@]}
  if [[ $n -lt 2 ]]; then
    printf '%s' "$HOME"
    return
  fi
  local p="${GCP_SEG_TOKENS[1]}"
  # Skip a leading flag (cd -P/-L, Set-Location -LiteralPath/-Path)
  if [[ "$p" == -* ]] && [[ $n -ge 3 ]]; then
    p="${GCP_SEG_TOKENS[2]}"
  fi
  p=$(gcp_expand_tilde "$p")
  if gcp_is_abs_path "$p"; then
    printf '%s' "$p"
  elif [[ -n "$base" ]]; then
    printf '%s/%s' "$base" "$p"
  else
    printf '%s' "$p"
  fi
}

# ------------------------------------------------------------------
# Composed helpers — the single resolver
# ------------------------------------------------------------------

# Does this segment change the working directory to a NAMED target?
# `cd` with no argument means $HOME and counts. Bare `pushd` / `popd` rotate a
# stack we cannot model, so they are deliberately NOT matched — leaving the
# accumulated target untouched is the conservative reading.
gcp_is_cd_segment() {
  local seg="$1"
  case "$seg" in
    cd|cd[[:space:]]*) return 0 ;;
    pushd[[:space:]]*) return 0 ;;
    [Ss]et-[Ll]ocation|[Ss]et-[Ll]ocation[[:space:]]*) return 0 ;;
  esac
  return 1
}

# Strip leading `VAR=value` assignments from a segment (`FOO=bar git commit`).
# The stripper must consume the SAME character class the condition tests: an
# earlier version used ${seg#* } (literal space only), so `FOO=bar<TAB>git` spun
# forever — and a PreToolUse hook that never returns hangs the tool call outright.
gcp_strip_env_assignments() {
  local seg="$1" guard=0
  while [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]] ]]; do
    seg="${seg#*[[:space:]]}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
    guard=$((guard+1))
    if [[ "$guard" -gt 32 ]]; then
      # Guard tripped: the parse is no longer trustworthy. Say so rather than
      # returning a clean-looking result the caller will treat as authoritative.
      GCP_PARSE_DEGRADED=1
      break
    fi
  done
  printf '%s' "$seg"
}

# Split a command into segments on && || ; | & and newline, OUTSIDE quotes.
# Populates GCP_SEGMENTS[]. Quotes and every other character are preserved
# verbatim so gcp_tokenize_segment can do its own quote handling downstream.
gcp_split_command() {
  local s="$1" i n ch nx cur="" in_sq=0 in_dq=0
  GCP_SEGMENTS=()
  n=${#s}
  for ((i=0; i<n; i++)); do
    ch="${s:i:1}"
    if [[ $in_sq -eq 1 ]]; then
      cur+="$ch"
      [[ "$ch" == "'" ]] && in_sq=0
      continue
    fi
    if [[ $in_dq -eq 1 ]]; then
      # A backslash inside double quotes escapes the next character; carry both
      # so an escaped quote does not end the string early.
      if [[ "$ch" == '\' ]] && [[ $((i+1)) -lt $n ]]; then
        cur+="$ch"; i=$((i+1)); cur+="${s:i:1}"; continue
      fi
      cur+="$ch"
      [[ "$ch" == '"' ]] && in_dq=0
      continue
    fi
    case "$ch" in
      "'") in_sq=1; cur+="$ch" ;;
      '"') in_dq=1; cur+="$ch" ;;
      '\')
        # Outside quotes a backslash escapes the next character, including a
        # separator: `echo \; foo` is one command, not two.
        if [[ $((i+1)) -lt $n ]]; then
          cur+="$ch"; i=$((i+1)); cur+="${s:i:1}"
        else
          cur+="$ch"
        fi
        ;;
      '&'|'|')
        nx=""
        [[ $((i+1)) -lt $n ]] && nx="${s:i+1:1}"
        [[ "$nx" == "$ch" ]] && i=$((i+1))   # consume the second char of && / ||
        GCP_SEGMENTS+=("$cur"); cur=""
        ;;
      ';'|$'\n')
        GCP_SEGMENTS+=("$cur"); cur=""
        ;;
      *) cur+="$ch" ;;
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

  gcp_split_command "$cmd"
  local n=${#GCP_SEGMENTS[@]} i seg cd_target="" base
  for ((i=0; i<n; i++)); do
    seg="${GCP_SEGMENTS[$i]}"
    # trim both ends
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg%"${seg##*[![:space:]]}"}"
    [[ -n "$seg" ]] || continue
    seg="$(gcp_strip_env_assignments "$seg")"
    [[ -n "$seg" ]] || continue

    base="$cd_target"
    [[ -n "$base" ]] || base="$cwd"

    if gcp_is_cd_segment "$seg"; then
      cd_target="$(gcp_parse_cd_target "$seg" "$base")"
      continue
    fi
    case "$seg" in
      git|git[[:space:]]*) ;;
      *) continue ;;
    esac
    gcp_analyze_git_segment "$seg" "$base"
    if [[ "${GCP_SEG_IS_COMMIT:-0}" -eq 1 ]]; then
      GCP_IS_COMMIT=1
      if [[ -n "${GCP_SEG_WORK_TREE:-}" ]]; then
        GCP_TARGET_DIR="$GCP_SEG_WORK_TREE"
      elif [[ -n "${GCP_SEG_GIT_DIR:-}" ]]; then
        # `--git-dir=/repo/.git` implies the work tree is /repo.
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

# ===========================================================================
# Self-test
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
  # The orchestrator's own cherry-pick shape. A -C on an earlier, non-commit
  # segment repointed the review-record gate at another repo -> rc=0 fail-open.
  _eq "earlier -C must not leak" "1|" "$(_r "git -C /elsewhere log --oneline -1 && git add -A && git $V -m x" /cwd)"
  _eq "-C inside a commit MESSAGE must not leak" "1|" "$(_r "git $V -m 'use git -C /other next time'" /cwd)"
  _eq "-C in an echoed string must not leak" "1|" "$(_r "echo \"git -C /other status\" && git $V -m x" /cwd)"

  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) _gcp_self_test; exit $? ;;
  esac
fi
