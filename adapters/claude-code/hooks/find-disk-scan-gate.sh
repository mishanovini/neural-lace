#!/bin/bash
# find-disk-scan-gate.sh — PreToolUse (Bash|PowerShell) gate: BLOCKS drive-wide
# filesystem scans.
#
# Amendment (2026-07-23, docs/plans/agent-efficiency-fixes-2026-07.md
# "In-flight amendments" section, orchestrating session 29f2930a, operator
# authorized "build the efficiency batch"): T4 was originally planned as a
# WARN hook — that plan text is superseded here. This gate is BLOCK-mode by
# decision: a drive-wide scan has no legitimate use on this machine, so
# warning and letting it proceed anyway buys nothing. The existing sibling
# find-scan-warn.sh (non-blocking) is UNCHANGED and still ships — it covers
# the broader, softer class (`find ~`, `find $HOME`) where a false positive
# is more plausible. This gate covers only the strictly-narrower,
# strictly-worse "whole drive" class.
#
# GOLDEN SCENARIO (docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md):
# live PID 14916 ran `find / -iname scope-enforcement-gate*` — a FULL C:\
# drive scan through the MSYS2 emulation layer — measured at ~13% of a core
# for MINUTES before being killed by hand. This gate would have BLOCKED that
# command before it ever executed.
#
# WHY drive-wide scans are pathological here (not merely slow):
#   - Git Bash / MSYS2 translates `/` to the whole C:\ filesystem (not a
#     POSIX-rooted sandbox) — a bare `find /` walks every file on the drive:
#     Windows\, Program Files\, node_modules trees, everything.
#   - Windows Defender real-time protection inspects each newly-opened path,
#     so the OS-level cost compounds with the shell-level walk cost.
#   - The repo root, the harness hooks, and $HOME are all independently
#     resolvable in O(1) (git rev-parse --show-toplevel, ~/.claude/hooks/,
#     adapters/claude-code/hooks/, $HOME) — no query a disk-wide scan
#     answers isn't answered faster and cheaper by a scoped one.
#
# WHAT THIS GATE CATCHES (BLOCK, exit 2) — the ROOT argument is what
# matters, not the mere presence of the command name:
#   - `find` with ANY root (of possibly several) that is a drive-wide root:
#     bare `/`, bare MSYS drive mounts `/c`, `/c/`, bare WSL mounts
#     `/mnt/<letter>`, `/mnt/<letter>/`, or a bare Windows drive letter `C:`,
#     `C:\`, `C:/`. Options before the root (find's roots precede its
#     expression) are skipped; a trailing `-maxdepth N` (any N) after a
#     drive-wide root does NOT make the scan safe — still blocked.
#   - `grep -r`/`-R`/`--recursive`/`--dereference-recursive` (case-
#     INsensitive — `-R` and `-r` are both recognized, including any
#     combined short-flag form, e.g. `-rn`, `-Rn`, `-irn`) or `rg`
#     (recursive by default) whose search path is one of the same
#     drive-wide roots.
#   - PowerShell `Get-ChildItem -Recurse` (path in any argument order,
#     including named `-Path`) whose path argument is a drive-wide root.
#   - Any of the above inside a command chain (`&&`, `;`, `|`, `||`) — every
#     segment is scanned independently; ANY matching segment blocks the
#     whole command.
#
# WHAT THIS GATE NEVER BLOCKS (the FP budget — zero blocks on scoped
# searches, by construction of the root-only check above):
#   - `find .`, `find docs/`, `find "$HOME/.claude/hooks" -name "*.sh"`, or
#     any other relative or specifically-named absolute path.
#   - `rg pattern src/`, `grep -r pattern ./lib` — scoped recursion.
#   - `Get-ChildItem -Recurse .` or with no explicit path (defaults to cwd).
#   - Non-matching commands entirely (cheap keyword pre-filter short-circuits).
#
# TEACHING (see _fdsg_block_message): names the exact command + matched
# segment + root, explains the CPU/Defender mechanism with the measured
# figure, and points at the cheap alternatives — the Glob tool (scoped
# glob, single ripgrep pass, no shell spawn), the Grep tool (content
# search), `ls ~/.claude/hooks/` / `ls adapters/claude-code/hooks/` for
# harness-hook discovery (the actual thing the golden-scenario command was
# hunting for), and `git rev-parse --show-toplevel` for repo roots.
#
# WAIVER (structured escape hatch, house pattern — copied from
# harness-hygiene-scan.sh's shape exactly): a fresh (<1h) file at
#   <repo-or-HOME>/.claude/state/find-disk-scan-waiver-*.txt
# naming BOTH purpose clauses (lib/waiver-purpose-clause.sh) AND a
# "Command:" line whose content is a substring of (or contains) the actual
# blocked command. Suppresses the block for THIS command, this run only;
# every use is ledger-logged (lib/signal-ledger.sh, event "waiver"). Fails
# closed: missing/stale/clause-less/non-matching waivers do not unlock. The
# block message instructs writing this file with the Write tool, not a
# shell command — a Bash/PowerShell waiver-write would itself be a command
# containing the quoted original blocked command text and would pass back
# through this same PreToolUse gate (batch-review Major finding: this was
# a real re-block risk before the quote-aware segment-splitter fix below;
# the Write-tool instruction removes the risk structurally, independent of
# how well the splitter parses any given quoting shape).
#
# FAIL-OPEN: no jq / empty payload / malformed JSON / tool other than
# Bash|PowerShell -> exit 0 (allow). This gate teaches; it must never brick
# a session on a parser bug.
#
# RESIDUALS (documented, not caught — honest gaps, not silently assumed away):
#   - `bash -c "find / ..."`, `ssh host 'find / ...'`, `docker exec ...
#     find /` — a scan hidden one level down inside a nested quoted string
#     handed to another interpreter is not unwrapped; this gate only parses
#     the OUTER command string's own segments.
#   - Exotic quoting/escaping: a root built at runtime via command
#     substitution or variable expansion (`R=/; find "$R"`), base64-encoded
#     commands, or `$'...'` ANSI-C quoting of the root is not evaluated —
#     only a literal, directly-visible root token is checked.
#   - The quote-aware segment splitter (_fdsg_split_segments) tracks single-
#     and double-quote state char-by-char but does NOT track parenthesis
#     depth or backslash-escaped quotes: an unquoted subshell/command-
#     substitution containing a top-level-looking separator (`echo $(echo
#     a && echo b)`) could still split at the wrong point, and a backslash-
#     escaped quote inside a double-quoted span (`"foo\"bar"`) ends the
#     quote-tracking early. Neither is evaluated for a masked drive-wide
#     root the way the common/documented quoting shapes above are.
#   - PowerShell aliases for Get-ChildItem (`gci`, `ls`, `dir`) are not
#     recognized — only the literal cmdlet name `Get-ChildItem`.
#   - `find`'s pre-path global options are handled for the common set
#     (-H/-L/-P/-O0..3/-D <opts>); an option this gate does not know about,
#     placed before the root, could shift the parse and miss a root.
#
# Self-test: bash find-disk-scan-gate.sh --self-test
#
# Exit codes:
#   0 — allowed (scoped search, non-matching command, waived, or fail-open)
#   2 — blocked (stderr explains; {"decision":"block"} JSON on stdout)

_FDSG_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
_FDSG_SELF_DIR="$(dirname "$_FDSG_SELF" 2>/dev/null)"
# shellcheck source=lib/waiver-purpose-clause.sh
source "$_FDSG_SELF_DIR/lib/waiver-purpose-clause.sh" 2>/dev/null || true
# shellcheck source=lib/signal-ledger.sh
source "$_FDSG_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true

# ============================================================
# Detection helpers
# ============================================================

# A drive-wide root: bare POSIX root, bare MSYS drive mount (with optional
# trailing slash), bare WSL mount, or a bare Windows drive letter (with 0-2
# trailing slash/backslash chars). Anchored full-string match — a root with
# MORE path components after it (/c/Users, C:\Users) is scoped and does NOT
# match (verified: no false positive on any real subdirectory path).
_FDSG_DRIVE_WIDE_RE='^(/|/[A-Za-z]/?|/mnt/[A-Za-z]/?|[A-Za-z]:[\\/]{0,2})$'

_fdsg_is_drive_wide_root() {
  printf '%s' "$1" | grep -qE "$_FDSG_DRIVE_WIDE_RE"
}

# Tokenize a command segment respecting single/double quotes. Populates
# global array FDSG_TOKENS. (Deliberately duplicated rather than sourced
# from scope-enforcement-gate.sh — this gate stays single-file/dependency
# -light per house convention for small gates; the shape is the same.)
_fdsg_tokenize() {
  local s="$1" i ch n cur="" in_dq=0 in_sq=0 have=0
  FDSG_TOKENS=()
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
          FDSG_TOKENS+=("$cur"); cur=""; have=0
        fi
        ;;
      *) cur+="$ch"; have=1 ;;
    esac
  done
  if [[ -n "$cur" ]] || [[ $have -eq 1 ]]; then
    FDSG_TOKENS+=("$cur")
  fi
}

# Split a full command string into segments on TOP-LEVEL (unquoted) &&, ;,
# |, || only. Quote-AWARE: a separator character appearing inside a single-
# or double-quoted span is part of that span's literal text, not a break —
# fixes the quote-unaware-splitting Major finding (batch review): the prior
# sed-based version split on ANY occurrence of these characters regardless
# of quoting, so `git commit -m "guard against && find / scans"` and
# `echo "do not run ; find / here"` were hard-blocked on quoted PROSE that
# merely mentions a separator + `find /`-shaped text, and the gate's own
# waiver-remedy snippet (which echoes the original blocked command back
# inside a quoted `printf 'Command: %s\n' "..."` argument) could re-trip
# itself the same way when the operator re-ran it. Character-by-character
# scan mirrors _fdsg_tokenize's quote-state tracking exactly. Prints one
# segment per line (always newline-terminated, including the last one —
# `while read` drops an unterminated last line otherwise).
_fdsg_split_segments() {
  local s="$1" i n ch in_sq=0 in_dq=0 cur=""
  n=${#s}
  for ((i=0; i<n; i++)); do
    ch="${s:i:1}"
    if [[ $in_sq -eq 1 ]]; then
      cur+="$ch"
      [[ "$ch" == "'" ]] && in_sq=0
      continue
    fi
    if [[ $in_dq -eq 1 ]]; then
      cur+="$ch"
      [[ "$ch" == '"' ]] && in_dq=0
      continue
    fi
    case "$ch" in
      "'") in_sq=1; cur+="$ch" ;;
      '"') in_dq=1; cur+="$ch" ;;
      '&')
        if [[ "${s:i+1:1}" == "&" ]]; then
          printf '%s\n' "$cur"; cur=""; i=$((i+1))
        else
          cur+="$ch"
        fi
        ;;
      ';')
        printf '%s\n' "$cur"; cur=""
        ;;
      '|')
        if [[ "${s:i+1:1}" == "|" ]]; then
          printf '%s\n' "$cur"; cur=""; i=$((i+1))
        else
          printf '%s\n' "$cur"; cur=""
        fi
        ;;
      *)
        cur+="$ch"
        ;;
    esac
  done
  printf '%s\n' "$cur"
}

# _fdsg_check_find <tokens...>  (tokens[0] == "find")
# Sets FDSG_MATCH_ROOT on a drive-wide root; returns 0 if found, 1 otherwise.
_fdsg_check_find() {
  local -a args=("$@")
  local n=${#args[@]} i=1 tok
  # Skip recognized pre-path global options (find -H/-L/-P/-Olevel/-D optarg).
  while [[ $i -lt $n ]]; do
    tok="${args[$i]}"
    case "$tok" in
      -H|-L|-P|-O0|-O1|-O2|-O3) i=$((i+1)) ;;
      -D) i=$((i+2)) ;;
      *) break ;;
    esac
  done
  # Collect roots: consecutive non-flag tokens (find's paths precede its
  # expression — the first flag-shaped/expression-operator token ends the
  # root list, whatever it is: -maxdepth, -iname, (, !, etc.).
  while [[ $i -lt $n ]]; do
    tok="${args[$i]}"
    case "$tok" in
      -*|"("|")"|"!"|",")
        break
        ;;
      *)
        if _fdsg_is_drive_wide_root "$tok"; then
          FDSG_MATCH_ROOT="$tok"
          return 0
        fi
        i=$((i+1))
        ;;
    esac
  done
  return 1
}

# _fdsg_check_grep_rg <tokens...>  (tokens[0] basename is "grep" or "rg")
_fdsg_check_grep_rg() {
  local -a args=("$@")
  local n=${#args[@]} base="${args[0]}"
  base="${base##*/}"
  local is_rg=0 is_recursive_grep=0 j
  if [[ "$base" == "rg" ]]; then
    is_rg=1
  elif [[ "$base" == "grep" ]]; then
    for ((j=1; j<n; j++)); do
      case "${args[$j]}" in
        --recursive|--dereference-recursive) is_recursive_grep=1 ;;
        -*)
          # Case-insensitive: -r AND -R both mean recursive (grep(1) -R
          # differs from -r only in symlink-following, not recursion).
          # Fix for the missed-uppercase-R Major finding (batch review):
          # the prior `-*r*` glob was case-sensitive and let `-R`/`-Rn`
          # slip through uncaught.
          if [[ "${args[$j]}" == -*[rR]* ]] && [[ "${args[$j]}" != --* ]]; then
            is_recursive_grep=1
          fi
          ;;
      esac
    done
  else
    return 1
  fi
  [[ "$is_rg" -eq 1 || "$is_recursive_grep" -eq 1 ]] || return 1

  # Non-flag tokens after the command name: the pattern is always the
  # first one; a search-root path is only present when there is a SECOND
  # non-flag token. The LAST non-flag token is treated as the root.
  local -a nonflags=()
  local k
  for ((k=1; k<n; k++)); do
    case "${args[$k]}" in
      -*) : ;;
      *) nonflags+=("${args[$k]}") ;;
    esac
  done
  [[ ${#nonflags[@]} -ge 2 ]] || return 1
  local root="${nonflags[${#nonflags[@]}-1]}"
  if _fdsg_is_drive_wide_root "$root"; then
    FDSG_MATCH_ROOT="$root"
    return 0
  fi
  return 1
}

# _fdsg_check_gci <tokens...>  (tokens[0] case-insensitively "Get-ChildItem")
_fdsg_check_gci() {
  local -a args=("$@")
  local n=${#args[@]} has_recurse=0 k argl
  local -a nonflags=()
  for ((k=1; k<n; k++)); do
    argl="${args[$k],,}"
    case "$argl" in
      -recurse) has_recurse=1 ;;
      -*) : ;;
      *) nonflags+=("${args[$k]}") ;;
    esac
  done
  [[ "$has_recurse" -eq 1 ]] || return 1
  [[ ${#nonflags[@]} -ge 1 ]] || return 1  # no explicit path -> defaults to cwd, safe
  local p
  for p in "${nonflags[@]}"; do
    if _fdsg_is_drive_wide_root "$p"; then
      FDSG_MATCH_ROOT="$p"
      return 0
    fi
  done
  return 1
}

# _fdsg_scan_segment <segment-string>
# Sets FDSG_MATCH_CMD + FDSG_MATCH_ROOT and returns 0 on a drive-wide scan
# in this segment; returns 1 otherwise.
_fdsg_scan_segment() {
  local seg="$1"
  seg="${seg#"${seg%%[![:space:]]*}"}"
  seg="${seg%"${seg##*[![:space:]]}"}"
  [[ -z "$seg" ]] && return 1
  _fdsg_tokenize "$seg"
  [[ ${#FDSG_TOKENS[@]} -eq 0 ]] && return 1
  local cmd0_base="${FDSG_TOKENS[0]##*/}"
  local cmd0_lc="${cmd0_base,,}"
  case "$cmd0_lc" in
    find)
      _fdsg_check_find "${FDSG_TOKENS[@]}" && { FDSG_MATCH_CMD="$seg"; return 0; }
      ;;
    grep|rg)
      _fdsg_check_grep_rg "${FDSG_TOKENS[@]}" && { FDSG_MATCH_CMD="$seg"; return 0; }
      ;;
    get-childitem)
      _fdsg_check_gci "${FDSG_TOKENS[@]}" && { FDSG_MATCH_CMD="$seg"; return 0; }
      ;;
  esac
  return 1
}

# _fdsg_scan_command <full-command-string>
# Splits into segments, scans each; sets FDSG_MATCH_CMD/FDSG_MATCH_ROOT on
# the first hit. Returns 0 if ANY segment matches, 1 if none do.
_fdsg_scan_command() {
  local seg
  while IFS= read -r seg; do
    _fdsg_scan_segment "$seg" && return 0
  done < <(_fdsg_split_segments "$1")
  return 1
}

# ============================================================
# Waiver check (structured hatch, harness-hygiene-scan.sh shape exactly)
# ============================================================
_fdsg_is_waived() {
  local cmd="$1" state_dir="$2" f wcmd
  [[ -d "$state_dir" ]] || return 1
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if declare -F waiver_has_purpose_clauses >/dev/null 2>&1; then
      waiver_has_purpose_clauses "$f" || continue
    fi
    wcmd=$(grep -iE '^[[:space:]]*command[[:space:]]*:' "$f" 2>/dev/null \
      | sed -E 's/^[[:space:]]*[Cc]ommand[[:space:]]*:[[:space:]]*//' | head -1)
    [[ -z "$wcmd" ]] && continue
    if [[ "$cmd" == *"$wcmd"* ]] || [[ "$wcmd" == *"$cmd"* ]]; then
      printf '%s' "$f"
      return 0
    fi
  done < <(find "$state_dir" -maxdepth 1 -type f -name 'find-disk-scan-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null)
  return 1
}

# ============================================================
# Block message
# ============================================================
_fdsg_block_message() {
  local full_cmd="$1" matched_seg="$2" root="$3" state_dir="$4"
  {
    echo ""
    echo "================================================================"
    echo "FIND-DISK-SCAN-GATE — BLOCKED"
    echo "Gate: $_FDSG_SELF"
    echo "================================================================"
    echo ""
    echo "Command: $full_cmd"
    if [[ "$matched_seg" != "$full_cmd" ]]; then
      echo "Matched segment: $matched_seg"
    fi
    echo "Matched drive-wide root: $root"
    echo ""
    echo "WHY: on this Windows machine, a bare / (or a bare drive mount"
    echo "/c, /mnt/<letter>, or a bare Windows drive letter C:\\) resolves"
    echo "through the Git Bash / MSYS2 layer to the ENTIRE drive — a scan"
    echo "walks every file on it (every directory stat is an MSYS2 syscall)"
    echo "AND Windows Defender real-time protection inspects each opened"
    echo "path. Measured live 2026-07-20: \`find / -iname"
    echo "scope-enforcement-gate*\` (PID 14916) ran at ~13% of a core for"
    echo "MINUTES before being killed by hand"
    echo "(docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md)."
    echo "There is no legitimate reason to scan a whole drive on this box."
    echo ""
    echo "Use instead:"
    echo "  - Glob tool     — scoped glob (\`**/pattern\`), single ripgrep pass"
    echo "  - Grep tool     — file-content search, permission-integrated"
    echo "  - harness hooks — \`ls ~/.claude/hooks/\` or"
    echo "                    \`ls adapters/claude-code/hooks/\`"
    echo "  - repo root     — \`git rev-parse --show-toplevel\`"
    echo ""
    echo "Hatch (cost: unlocks THIS command for <1h, ledger-logged — never a"
    echo "blanket suppression): a genuinely-needed one-off drive-wide scan"
    echo "gets a fresh (<1h) structured waiver naming BOTH purpose clauses"
    echo "AND the command. Use the Write tool (NOT a shell command — writing"
    echo "the waiver via Bash/PowerShell would echo this blocked command back"
    echo "through this same gate and could re-trip it) to create:"
    echo "  $state_dir/find-disk-scan-waiver-<unix-timestamp>.txt"
    echo "with this content:"
    echo "  Purpose: this gate exists to prevent disk-wide find/grep/rg/Get-ChildItem scans"
    echo "  Because: <why this specific one-off is genuinely needed>"
    echo "  Command: $full_cmd"
    echo "Then re-run the original command."
    echo "================================================================"
  } >&2
  cat <<JSON
{"decision": "block", "reason": "find-disk-scan-gate: drive-wide filesystem scan detected ($root). See stderr for why and the alternatives/waiver."}
JSON
}

# ============================================================
# --self-test
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  PASSED=0
  FAILED=0
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t fdsgst)
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMP"' EXIT

  # JSON-string-escape stdin (jq preferred; manual fallback keeps the
  # self-test runnable even without jq on PATH).
  _fdsg_json_str() {
    local s
    s=$(cat)
    if command -v jq >/dev/null 2>&1; then
      printf '%s' "$s" | jq -Rs .
    else
      s="${s//\\/\\\\}"
      s="${s//\"/\\\"}"
      printf '"%s"' "$s"
    fi
  }

  # _block_test <label> <command> [tool_name]
  _block_test() {
    local label="$1" cmd="$2" tool="${3:-Bash}" rc out esc
    esc=$(printf '%s' "$cmd" | _fdsg_json_str)
    out=$(printf '{"tool_name":"%s","tool_input":{"command":%s}}' "$tool" "$esc" \
          | CLAUDE_STATE_DIR="$TMP/state-unused" bash "$_FDSG_SELF" 2>"$TMP/err.txt")
    rc=$?
    local err; err=$(cat "$TMP/err.txt" 2>/dev/null)
    if [[ "$rc" == "2" ]] && [[ "$err" == *"BLOCKED"* ]] && [[ "$out" == *'"decision": "block"'* ]]; then
      echo "self-test: PASS (block) — $label" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test: FAIL (block) — $label (rc=$rc, stderr='${err:0:80}')" >&2
      FAILED=$((FAILED+1))
    fi
  }

  # _allow_test <label> <command> [tool_name]
  _allow_test() {
    local label="$1" cmd="$2" tool="${3:-Bash}" rc esc
    esc=$(printf '%s' "$cmd" | _fdsg_json_str)
    printf '{"tool_name":"%s","tool_input":{"command":%s}}' "$tool" "$esc" \
          | bash "$_FDSG_SELF" >"$TMP/out.txt" 2>"$TMP/err.txt"
    rc=$?
    if [[ "$rc" == "0" ]]; then
      echo "self-test: PASS (allow) — $label" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test: FAIL (allow) — $label (rc=$rc, stderr='$(cat "$TMP/err.txt" 2>/dev/null | head -c 80)')" >&2
      FAILED=$((FAILED+1))
    fi
  }

  # ---- BLOCK scenarios ----
  _block_test "golden scenario verbatim (2026-07-20 live PID 14916)" 'find / -iname "scope-enforcement-gate*"'
  _block_test "find /c/ drive mount" 'find /c/ -name x'
  _block_test "grep -r rooted at /" 'grep -r pattern /'
  _block_test "grep -R (uppercase recursive) rooted at /" 'grep -R pattern /'
  _block_test "grep -Rn (uppercase combined short-flag) rooted at /c/" 'grep -Rn pattern /c/'
  _block_test "rg rooted at bare Windows drive" 'rg x C:\'
  _block_test "PowerShell Get-ChildItem -Recurse C:\\" 'Get-ChildItem C:\ -Recurse' "PowerShell"
  _block_test "chained: cd foo && find /" 'cd foo && find / -name x'

  # Flat-shape payload (.command at top level, no tool_input wrapper) —
  # house convention per the jq filter '.tool_input.command // .command // ""'.
  FLAT_RC=$(printf '{"tool_name":"Bash","command":"find / -iname x"}' \
            | bash "$_FDSG_SELF" >/dev/null 2>"$TMP/flat_err.txt"; echo $?)
  FLAT_ERR=$(cat "$TMP/flat_err.txt" 2>/dev/null)
  if [[ "$FLAT_RC" == "2" ]] && [[ "$FLAT_ERR" == *"BLOCKED"* ]]; then
    echo "self-test: PASS (block) — flat-shape payload (.command, no tool_input)" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test: FAIL (block) — flat-shape payload (rc=$FLAT_RC)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- ALLOW scenarios ----
  _allow_test "find . scoped" 'find . -name x'
  _allow_test "find docs scoped" 'find docs -type f'
  _allow_test 'find "$HOME/.claude/hooks" scoped' 'find "$HOME/.claude/hooks" -name "*.sh"'
  _allow_test "rg scoped to src/" 'rg pattern src/'
  _allow_test "Get-ChildItem -Recurse . scoped" 'Get-ChildItem -Recurse .' "PowerShell"
  _allow_test "non-find command" 'echo hello world'

  # ---- NEGATIVE: quoted separator + find/-root-shaped PROSE must never
  # split/match (quote-unaware-splitting Major finding, batch review) ----
  _allow_test 'git commit -m with quoted && find / inside the message' 'git commit -m "guard against && find / scans"'
  _allow_test 'echo with quoted ; find / inside the string' 'echo "do not run ; find / here"'

  # Malformed JSON -> fail-open (allow).
  MALFORMED_RC=$(printf '{not json at all' | bash "$_FDSG_SELF" >/dev/null 2>"$TMP/malformed_err.txt"; echo $?)
  if [[ "$MALFORMED_RC" == "0" ]]; then
    echo "self-test: PASS (allow) — malformed JSON fails open" >&2
    PASSED=$((PASSED+1))
  else
    echo "self-test: FAIL (allow) — malformed JSON expected rc=0, got $MALFORMED_RC" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- Waiver scenario: fresh valid waiver -> ALLOW + ledger log ----
  WAIVER_STATE="$TMP/waiver-state/.claude/state"
  mkdir -p "$WAIVER_STATE"
  WAIVED_CMD='find / -iname "scope-enforcement-gate*"'
  {
    printf 'Purpose: this gate exists to prevent disk-wide find/grep/rg/Get-ChildItem scans\n'
    printf 'Because: this is a self-test fixture verifying the waiver hatch, not a real one-off\n'
    printf 'Command: %s\n' "$WAIVED_CMD"
  } > "$WAIVER_STATE/find-disk-scan-waiver-selftest.txt"
  WAIVER_LEDGER="$TMP/waiver-ledger.jsonl"
  WESC=$(printf '%s' "$WAIVED_CMD" | _fdsg_json_str)
  WAIVER_RC=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$WESC" \
    | CLAUDE_STATE_DIR="$WAIVER_STATE" HARNESS_SELFTEST=1 SIGNAL_LEDGER_PATH="$WAIVER_LEDGER" \
      bash "$_FDSG_SELF" >/dev/null 2>"$TMP/waiver_err.txt"; echo $?)
  WAIVER_OK=1
  if [[ "$WAIVER_RC" != "0" ]]; then
    WAIVER_OK=0
    echo "self-test: FAIL (waiver) — fresh valid waiver expected rc=0, got $WAIVER_RC" >&2
  fi
  if [[ ! -f "$WAIVER_LEDGER" ]] || ! grep -q '"gate":"find-disk-scan-gate"' "$WAIVER_LEDGER" 2>/dev/null \
     || ! grep -q '"event":"waiver"' "$WAIVER_LEDGER" 2>/dev/null; then
    WAIVER_OK=0
    echo "self-test: FAIL (waiver) — expected a ledger-logged waiver event, not found" >&2
  fi
  if [[ "$WAIVER_OK" -eq 1 ]]; then
    echo "self-test: PASS (waiver) — fresh valid waiver allows + ledger-logs" >&2
    PASSED=$((PASSED+1))
  else
    FAILED=$((FAILED+1))
  fi
  rm -f "$WAIVER_STATE/find-disk-scan-waiver-selftest.txt"

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed" >&2
  [[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
fi

# ============================================================
# Main hook logic
# ============================================================
FDSG_INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$FDSG_INPUT" ]] && [[ ! -t 0 ]]; then
  FDSG_INPUT=$(cat 2>/dev/null || echo "")
fi
[[ -z "$FDSG_INPUT" ]] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  exit 0  # cannot parse safely — fail open, never brick a session on a parser gap
fi

FDSG_TOOL_NAME=$(printf '%s' "$FDSG_INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
if [[ "$FDSG_TOOL_NAME" != "Bash" ]] && [[ "$FDSG_TOOL_NAME" != "PowerShell" ]]; then
  exit 0
fi

FDSG_CMD=$(printf '%s' "$FDSG_INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null)
[[ -z "$FDSG_CMD" ]] && exit 0

# Cheap pre-filter: none of the target command names appear -> pass through
# without the (still-cheap, but non-zero) segment/tokenize work.
if ! printf '%s' "$FDSG_CMD" | grep -qiE '(^|[[:space:];&|])(find|grep|rg|Get-ChildItem)([[:space:]]|$)'; then
  exit 0
fi

if ! _fdsg_scan_command "$FDSG_CMD"; then
  exit 0
fi

# Resolve state dir: repo-scoped when inside a git repo, else $HOME-scoped
# (this gate can fire outside a git repo; a global fallback still lets the
# waiver hatch work). CLAUDE_STATE_DIR always wins (test/override hook).
_FDSG_REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
FDSG_STATE_DIR="${CLAUDE_STATE_DIR:-${_FDSG_REPO_ROOT:-$HOME}/.claude/state}"

if FDSG_WFILE=$(_fdsg_is_waived "$FDSG_CMD" "$FDSG_STATE_DIR"); then
  command -v ledger_emit >/dev/null 2>&1 && \
    ledger_emit "find-disk-scan-gate" "waiver" "root=$FDSG_MATCH_ROOT waiver=$FDSG_WFILE cmd=${FDSG_CMD:0:120}"
  echo "[find-disk-scan-gate] ALLOW: fresh structured waiver covers this command ($FDSG_WFILE) — ledger-logged." >&2
  exit 0
fi

command -v ledger_emit >/dev/null 2>&1 && \
  ledger_emit "find-disk-scan-gate" "block" "root=$FDSG_MATCH_ROOT cmd=${FDSG_CMD:0:120}"
_fdsg_block_message "$FDSG_CMD" "$FDSG_MATCH_CMD" "$FDSG_MATCH_ROOT" "$FDSG_STATE_DIR"
exit 2
