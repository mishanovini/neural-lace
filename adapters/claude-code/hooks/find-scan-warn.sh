#!/bin/bash
# find-scan-warn.sh
#
# PreToolUse (Bash|PowerShell) hook — NON-BLOCKING WARN ONLY.
#
# Catches disk-wide `find /` / `find ~` / `find $HOME` scans and nudges the
# agent toward the cheap alternatives (Glob / Grep / `git rev-parse
# --show-toplevel` / `git ls-files`). On Windows Git Bash a full-tree `find`
# is pathological: every directory stat is a syscall through the MSYS2
# emulation layer and Windows Defender scans each opened path — a single
# `find / -maxdepth 6 -iname <repo>` was measured at ~65% of a core
# (docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md,
# Finding 3 / rec 6).
#
# Contract: this hook NEVER blocks. Every code path exits 0. A false positive
# costs one stderr line, never a blocked command — so it warns on broad roots
# and stays silent on scoped finds (`find .`, `find ./src`, `find adapters/`).
#
# Self-test:
#   bash find-scan-warn.sh --self-test
#
# Exit codes:
#   0 — always (warn is emitted to stderr on a broad-root match; otherwise silent)

# --- Broad-root detector ----------------------------------------------------
# Match a `find` command token (at start or after a shell separator) whose
# search root is a filesystem root or a home dir — NOT any absolute path.
# Deliberately does NOT match `find /specific/scoped/path` (scoped) — only bare
# roots followed by whitespace, a slash, or end-of-string.
#   Broad roots matched: /  ~  $HOME  ${HOME}  "$HOME"  bare drive mounts
#   /c /d … (the most disk-wide MSYS form)  and  /mnt/<letter> (WSL mounts).
#   A single-letter root followed by more letters (/etc, /home, /usr) is NOT a
#   drive → stays silent (scoped). Trailing space/slash/quote/end anchors it.
_FIND_SCAN_RE='(^|[[:space:];&|(])find[[:space:]]+"?(~|\$[{]?HOME[}]?|/mnt/[a-z]([[:space:]/"]|$)|/[a-z]?([[:space:]/"]|$))'

_find_scan_is_broad() {
  # $1 = raw command string; returns 0 if it looks like a disk-wide find
  printf '%s' "$1" | grep -qE "$_FIND_SCAN_RE"
}

_find_scan_warn_msg() {
  cat >&2 <<'EOF'
WARN (non-blocking): disk-wide `find` scan detected.
  On this machine a full-tree find can burn a CPU core for tens of seconds
  (every dir stat is an MSYS2 syscall; Defender scans each opened path).
  Prefer:
    • Glob tool  — `**/pattern`         (single ripgrep pass, no shell spawn)
    • Grep tool  — file-content search  (ripgrep, permission-integrated)
    • repo root  — `git rev-parse --show-toplevel`
    • in-repo    — `git ls-files '<glob>'`
  Scoped finds (`find . -name x`, `find adapters/ -type f`) are fine.
EOF
}

# ============================================================
# Self-test entry point (before any input parsing)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  PASS=0; FAIL=0
  # $1 = label, $2 = command, $3 = expect ("warn" | "silent")
  _t() {
    local label="$1" cmd="$2" expect="$3" rc out
    out=$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(printf '%s' "$cmd" | jq -R .)}}" \
          | bash "$0" 2>/tmp/find_scan_err_$$; ); rc=$?
    local err; err=$(cat /tmp/find_scan_err_$$ 2>/dev/null); rm -f /tmp/find_scan_err_$$
    local ok=1
    [[ "$rc" -ne 0 ]] && ok=0            # must ALWAYS exit 0
    if [[ "$expect" == "warn" ]]; then
      [[ -z "$err" ]] && ok=0            # warn cases must emit stderr
    else
      [[ -n "$err" ]] && ok=0            # silent cases must be silent
    fi
    if [[ "$ok" -eq 1 ]]; then
      echo "self-test: PASS — $label" >&2; PASS=$((PASS+1))
    else
      echo "self-test: FAIL — $label (rc=$rc, expect=$expect, stderr='${err:0:40}')" >&2; FAIL=$((FAIL+1))
    fi
  }
  _t "find / -maxdepth 6 (Finding-3 case)" 'find / -maxdepth 6 -iname neural-lace -type d' warn
  _t "find ~ recursive"                    'find ~ -name "*.md"'                            warn
  _t "find \$HOME"                          'find $HOME -type d'                             warn
  _t "find /c/Users broad"                 'find /c/Users -iname foo'                       warn
  _t "find /c bare drive"                  'find /c -iname foo'                             warn
  _t "find /d bare drive"                  'find /d -type f'                                warn
  _t "find /mnt/d WSL mount"               'find /mnt/d -name x'                            warn
  _t "find quoted \$HOME"                   'find "$HOME" -type d'                           warn
  _t "find brace \${HOME}"                  'find ${HOME} -name y'                           warn
  _t "cd then find /"                       'cd /tmp && find / -name x'                      warn
  _t "find . scoped"                        'find . -name "*.sh"'                            silent
  _t "find ./adapters scoped"              'find ./adapters -type f'                        silent
  _t "find adapters/ relative"             'find adapters/ -name x'                         silent
  _t "find src scoped"                      'find src -name "*.ts"'                          silent
  _t "find /etc scoped (not a drive)"      'find /etc -name hosts'                          silent
  _t "find /home/x scoped"                 'find /home/user -name z'                        silent
  _t "no find at all"                       'ls -la /'                                       silent
  _t "grep mentioning /"                    'grep -rn foo /etc/hosts'                        silent
  echo "" >&2
  echo "self-test summary: $PASS passed, $FAIL failed" >&2
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi

# ============================================================
# Main hook logic — read input, warn on broad find, ALWAYS exit 0
# ============================================================
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]] && [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi
[[ -z "$INPUT" ]] && exit 0

# Extract the command string (jq preferred; degrade to raw-string grep).
CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null)
fi
# jq-absent / malformed-JSON fallback: scan the raw payload directly. A warn is
# harmless, so a looser match here never risks a wrong block.
[[ -z "$CMD" ]] && CMD="$INPUT"

if _find_scan_is_broad "$CMD"; then
  _find_scan_warn_msg
fi
exit 0
