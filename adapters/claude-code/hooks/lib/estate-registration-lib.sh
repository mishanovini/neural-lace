#!/bin/bash
# estate-registration-lib.sh — no-orphan worktree/branch registration (T4).
#
# ============================================================================
# WHAT THIS IS
# ============================================================================
# The registration half of the Accountable Estate program's deterministic
# closure slice (docs/plans/accountable-estate-program-2026-07.md, task T4,
# design docs/designs/accountable-estate-2026-07-27.md §6c "no-orphan
# invariant"). It answers one question mechanically, never by memory or
# forensics: "who/what created this worktree, for which plan/task?"
#
#   "branches/worktrees are REGISTERED at creation (spawn-worktree gains a
#    ledger link to its work item) and de-registered by the closer. Anything
#    existing without a ledger link is definitionally unattributable ->
#    janitor flags it. Creation registers; closure de-registers; the diff is
#    always visible." -- design §6c
#
# One JSON file per open work-item, not an append-only ledger like
# admission-lib's would-block log: a worktree's registration is a STATE
# (open or closed), not an EVENT stream, and "is slug X currently open" must
# be a single stat + read, not a scan-and-fold over history. Closing MOVES
# the file (open dir -> closed dir), so `ls registrations/*.json` is always
# exactly "what's open right now" -- the same directory-as-truth idiom
# admission-lib's rate/ stamp-files use (review F9), applied to registration
# state instead of a rate window.
#
# ============================================================================
# API
# ============================================================================
#   reg_register <slug> <path> <branch> [key=value ...]
#     Writes an OPEN registration at $(reg_dir)/<slug>.json (tmp+mv, never a
#     truncating write). key=value labels are a closed enum (see
#     _reg_key_allowed) -- plan | task | session | who | kind. Fail-open:
#     an unwritable state dir is swallowed, never propagated to the caller
#     (this is spliced into spawn-worktree.sh's create path -- a broken
#     registration lib must never prevent a worktree from being created).
#     Always returns 0.
#
#   reg_close <slug> [disposition]
#     Moves $(reg_dir)/<slug>.json to $(reg_closed_dir)/<slug>.json, appending
#     closed_at/closed_epoch/disposition fields to the ORIGINAL bytes (no
#     JSON re-parse needed -- see the implementation note below). No-op,
#     rc 0, if the slug was never registered (a legacy/pre-mechanism worktree
#     being closed today has nothing to move -- that is itself the honest
#     "pre-existing, unattributed" case this slice's outcome metric names,
#     not a bug in this lib). Always returns 0.
#
#   reg_is_open <slug>            -> rc 0 iff an OPEN registration exists
#   reg_open_count                -> count of currently-open registrations
#                                     (builtin glob loop, no forks -- see the
#                                     admission-lib WIP-rung consumer, which
#                                     reads this SAME directory directly
#                                     rather than sourcing this lib, to avoid
#                                     a second source-and-parse on the
#                                     dispatch path)
#   reg_dir / reg_closed_dir / reg_state_dir  -> resolved paths
#
# ============================================================================
# STATE (sandboxed exactly like admission-lib.sh -- same convention, same
# reason: this lib is spliced into spawn-worktree.sh, whose OWN --self-test
# drives the real create/remove path. Without an identical guard, running
# spawn-worktree.sh --self-test would litter the OPERATOR'S REAL
# registrations dir with fixture slugs -- the exact Scenario-16/16b class
# defect admission-lib's own header documents having shipped once already.)
# ============================================================================
#   REG_STATE_DIR   default $HOME/.claude/state/estate  (explicit override
#                   always wins, including inside HARNESS_SELFTEST=1)
#   HARNESS_SELFTEST=1 with NO explicit REG_STATE_DIR -> diverts to
#                   ${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}}/reg-selftest-$$
#   registrations/          open work-items, one <slug>.json each
#   registrations/closed/   closed work-items, same filename, moved not copied
#
# admission-lib.sh's default ADM_ESTATE_SNAPSHOT lives at
# $HOME/.claude/state/estate/snapshot.json -- same parent directory as this
# lib's default REG_STATE_DIR, deliberately: T1's janitor, T3's admission
# lib, and T4's registrations all share one "estate" directory rather than
# inventing a fourth state root.
#
# SCRUB-AT-WRITE: same discipline as admission-lib.sh (design 6b edge 4) --
# registrations are read by the metric script and may be surfaced in reports,
# so label VALUES are whitelist-sanitized and KEYS are a closed enum. No raw
# cmdlines, prompts, or window titles are ever accepted.
#
# Self-test: bash estate-registration-lib.sh --self-test
# ============================================================================

# ---------------------------------------------------------------------------
# Paths (mirrors admission-lib.sh's adm_state_dir contract exactly)
# ---------------------------------------------------------------------------
reg_state_dir() {
  if [[ -n "${REG_STATE_DIR:-}" ]]; then printf '%s' "$REG_STATE_DIR"; return 0; fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    local base="${HARNESS_SELFTEST_DIR:-${TMPDIR:-/tmp}}"
    printf '%s' "${base%/}/reg-selftest-$$"
    return 0
  fi
  printf '%s' "$HOME/.claude/state/estate"
}

reg_dir()        { printf '%s' "$(reg_state_dir)/registrations"; }
reg_closed_dir() { printf '%s' "$(reg_dir)/closed"; }

_reg_now() {
  if [[ -n "${EPOCHSECONDS:-}" ]]; then printf '%s' "$EPOCHSECONDS"; return 0; fi
  local t; t="$(date +%s 2>/dev/null)" || t=0
  printf '%s' "$t"
}

_reg_iso() {
  local t; t="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || t=""
  printf '%s' "$t"
}

_reg_host() {
  local h="${REG_HOST_OVERRIDE:-${HOSTNAME:-}}"
  if [[ -z "$h" ]]; then h="$(uname -n 2>/dev/null)" || h="unknown"; fi
  h="${h%%.*}"
  h="${h//[^A-Za-z0-9._-]/_}"
  printf '%s' "${h:-unknown}"
}

# Whitelist-only sanitizer for label VALUES (mirrors admission-lib's
# _adm_scrub exactly -- duplicated rather than sourced so this lib has no
# load-bearing dependency on admission-lib.sh; the two are siblings, not a
# hierarchy).
_reg_scrub() {
  local v="$1"
  v="${v//[^A-Za-z0-9._-]/}"
  printf '%s' "${v:0:64}"
}

# Slug sanitizer: filenames on disk, so keep it filesystem-safe (mirrors
# spawn-worktree.sh's own sanitise_slug charset).
_reg_slug_clean() {
  printf '%s' "$1" | tr ' ' '-' | sed 's/[^a-zA-Z0-9._/-]//g; s#//*#/#g; s#/#_#g'
}

# Label KEYS are a closed enum, same discipline as admission-lib's
# _adm_key_allowed -- an unknown key is dropped, not written.
_reg_key_allowed() {
  case "$1" in
    plan|task|session|who|kind) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# reg_register <slug> <path> <branch> [key=value ...]
# ---------------------------------------------------------------------------
reg_register() {
  local slug path branch
  slug="$(_reg_slug_clean "${1:-}")"; shift 2>/dev/null || true
  path="${1:-}"; shift 2>/dev/null || true
  branch="${1:-}"; shift 2>/dev/null || true
  [[ -n "$slug" ]] || return 0   # nothing to register against -- fail-open

  local d; d="$(reg_dir)"
  mkdir -p "$d" 2>/dev/null || return 0   # unwritable state dir -- fail-open

  local labels="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    [[ "$k" != "$kv" ]] || continue
    _reg_key_allowed "$k" || continue
    v="$(_reg_scrub "$v")"
    [[ -n "$v" ]] || continue
    labels="$labels,\"$k\":\"$v\""
  done

  local now; now="$(_reg_now)"
  local tmp; tmp="$(mktemp "$d/.${slug}.XXXXXX" 2>/dev/null)" || return 0
  printf '{"schema":1,"slug":"%s","path":"%s","branch":"%s","created_at":"%s","created_epoch":%s,"host":"%s"%s}\n' \
    "$(_reg_scrub "$slug")" "${path//\"/}" "${branch//\"/}" "$(_reg_iso)" "$now" "$(_reg_host)" "$labels" \
    > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
  mv "$tmp" "$d/$slug.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# reg_close <slug> [disposition]
# ---------------------------------------------------------------------------
# Moves the OPEN record to the closed dir, appending closed_at/closed_epoch/
# disposition to the ORIGINAL bytes via parameter-expansion string surgery
# (strip the trailing "}", append the new fields, close the brace again) --
# deliberately NOT a JSON re-parse: this lib has no jq dependency and every
# other field (plan/task/session/who) must survive the close untouched
# regardless of what labels were present at register time. This is the same
# "don't re-derive what you already wrote" instinct as close-plan.sh's own
# inline-archival step.
reg_close() {
  local slug disposition
  slug="$(_reg_slug_clean "${1:-}")"; shift 2>/dev/null || true
  disposition="${1:-closed}"; shift 2>/dev/null || true
  [[ -n "$slug" ]] || return 0

  local d cd_dir; d="$(reg_dir)"; cd_dir="$(reg_closed_dir)"
  local src="$d/$slug.json"
  [[ -f "$src" ]] || return 0   # never registered -- honest no-op, not a failure

  mkdir -p "$cd_dir" 2>/dev/null || return 0

  local data; data="$(<"$src")" 2>/dev/null || return 0
  # Strip a trailing newline then the trailing "}".
  data="${data%$'\n'}"
  case "$data" in
    *'}') data="${data%\}}" ;;
    *) return 0 ;;   # not the shape we wrote -- leave it alone, fail-open
  esac

  local disp_clean; disp_clean="$(_reg_scrub "$disposition")"
  [[ -n "$disp_clean" ]] || disp_clean="closed"

  local tmp; tmp="$(mktemp "$cd_dir/.${slug}.XXXXXX" 2>/dev/null)" || return 0
  printf '%s,"closed_at":"%s","closed_epoch":%s,"disposition":"%s"}\n' \
    "$data" "$(_reg_iso)" "$(_reg_now)" "$disp_clean" > "$tmp" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; return 0; }
  mv "$tmp" "$cd_dir/$slug.json" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
  rm -f "$src" 2>/dev/null
  return 0
}

reg_is_open() {
  local slug; slug="$(_reg_slug_clean "${1:-}")"
  [[ -n "$slug" ]] || return 1
  [[ -f "$(reg_dir)/$slug.json" ]]
}

# reg_has_any_record <slug> -- rc 0 iff EITHER an open OR a closed
# registration exists for this slug. Consumed by estate-attribution-check.sh
# (T4's outcome-metric tool): a CLOSED record still answers "who/what created
# this" even though the item is no longer open, so it counts as attributable
# for the metric's purpose (a worktree whose closer ran but whose directory
# is somehow still on disk — e.g. the documented Windows husk-dir case — is
# a disposed-of item with a history, not an unattributable orphan).
reg_has_any_record() {
  local slug; slug="$(_reg_slug_clean "${1:-}")"
  [[ -n "$slug" ]] || return 1
  [[ -f "$(reg_dir)/$slug.json" ]] || [[ -f "$(reg_closed_dir)/$slug.json" ]]
}

# reg_open_count -- builtin glob loop, no forks (same idiom as
# admission-lib's adm_rate_in_window).
reg_open_count() {
  local d; d="$(reg_dir)"
  [[ -d "$d" ]] || { printf '%s' 0; return 0; }
  local n=0 f
  for f in "$d"/*.json; do
    [[ -e "$f" ]] || continue
    n=$(( n + 1 ))
  done
  printf '%s' "$n"
}

# ===========================================================================
# Self-test
# ===========================================================================
_reg_self_test() {
  local PASS=0 FAIL=0
  pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
  fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }

  local T; T="$(mktemp -d 2>/dev/null)" || { echo "cannot mktemp"; return 1; }
  export REG_STATE_DIR="$T/estate"
  export REG_HOST_OVERRIDE="testhost"
  mkdir -p "$REG_STATE_DIR"

  echo "Scenario 1: register creates an open registration with expected fields"
  reg_register wt-one "$T/wt-one" session/wt-one plan=my-plan task=T4 session=sess123 >/dev/null
  local f="$(reg_dir)/wt-one.json"
  [[ -f "$f" ]] && pass "registration file created" || fail "no file at $f"
  grep -q '"slug":"wt-one"' "$f" 2>/dev/null && pass "slug recorded" || fail "slug missing"
  grep -q '"plan":"my-plan"' "$f" 2>/dev/null && pass "plan label recorded" || fail "plan missing"
  grep -q '"task":"T4"' "$f" 2>/dev/null && pass "task label recorded" || fail "task missing"
  grep -q '"created_at":"20' "$f" 2>/dev/null && pass "created_at present (ISO)" || fail "created_at missing"

  echo "Scenario 2: reg_is_open reflects state before/after close"
  reg_is_open wt-one && pass "reg_is_open true for a registered slug" || fail "expected open"
  reg_is_open never-registered && fail "reg_is_open true for a slug never registered" \
    || pass "reg_is_open false for an unregistered slug"

  echo "Scenario 3: reg_open_count counts open registrations only"
  reg_register wt-two "$T/wt-two" session/wt-two >/dev/null
  local c; c="$(reg_open_count)"
  [[ "$c" == "2" ]] && pass "2 registrations -> count 2" || fail "expected 2, got $c"

  echo "Scenario 4: reg_close moves the record, preserves fields, adds disposition"
  reg_close wt-one "merged"
  [[ ! -f "$(reg_dir)/wt-one.json" ]] && pass "open record removed after close" || fail "open record still present"
  local cf="$(reg_closed_dir)/wt-one.json"
  [[ -f "$cf" ]] && pass "closed record created" || fail "no closed record at $cf"
  grep -q '"disposition":"merged"' "$cf" 2>/dev/null && pass "disposition recorded" || fail "disposition missing"
  grep -q '"plan":"my-plan"' "$cf" 2>/dev/null && pass "original plan label survives the close" || fail "plan label lost on close"
  grep -q '"closed_at":"20' "$cf" 2>/dev/null && pass "closed_at present" || fail "closed_at missing"
  reg_is_open wt-one && fail "reg_is_open still true after close" || pass "reg_is_open false after close"
  c="$(reg_open_count)"
  [[ "$c" == "1" ]] && pass "open count drops to 1 after closing one of two" || fail "expected 1, got $c"

  echo "Scenario 5: disallowed label keys dropped, values scrubbed (edge 4 discipline)"
  reg_register wt-three "$T/wt-three" session/wt-three cmdline=/Users/secret/ProductName repo="../../etc/passwd" plan="ok-plan" >/dev/null
  local f3="$(reg_dir)/wt-three.json"
  grep -q 'cmdline' "$f3" 2>/dev/null && fail "disallowed key 'cmdline' leaked" || pass "disallowed key 'cmdline' dropped"
  grep -q 'repo' "$f3" 2>/dev/null && fail "disallowed key 'repo' leaked (not in the enum for this lib)" || pass "disallowed key 'repo' dropped (registration enum is plan|task|session|who|kind)"
  grep -q '"plan":"ok-plan"' "$f3" 2>/dev/null && pass "allowed key survives alongside dropped ones" || fail "allowed key lost"

  echo "Scenario 6: closing an unregistered slug is a fail-open no-op"
  reg_close totally-unknown-slug "whatever"; local rc=$?
  [[ "$rc" == "0" ]] && pass "rc 0 closing an unregistered slug" || fail "rc $rc"
  [[ ! -f "$(reg_closed_dir)/totally-unknown-slug.json" ]] && pass "no bogus closed record fabricated" || fail "fabricated a closed record for a slug never registered"

  echo "Scenario 7: FAIL-OPEN under an unwritable state dir"
  local SAVED="$REG_STATE_DIR"
  export REG_STATE_DIR="/nonexistent-reg-$$/estate"
  reg_register wt-fail "$T/wt-fail" session/wt-fail; rc=$?
  [[ "$rc" == "0" ]] && pass "register rc 0 under unwritable dir (fail-open)" || fail "rc $rc"
  reg_close wt-fail; rc=$?
  [[ "$rc" == "0" ]] && pass "close rc 0 under unwritable dir (fail-open)" || fail "rc $rc"
  export REG_STATE_DIR="$SAVED"

  echo "Scenario 8: HOST self-test pollution guard (mirrors admission-lib Scenario 17)"
  unset REG_STATE_DIR
  local resolved; resolved="$(HARNESS_SELFTEST=1 reg_state_dir)"
  case "$resolved" in
    "$HOME/.claude/state/estate")
      fail "HARNESS_SELFTEST=1 still resolved to REAL state ($resolved)" ;;
    *) pass "HARNESS_SELFTEST=1 with no REG_STATE_DIR redirects away from real state ($resolved)" ;;
  esac
  local explicit; explicit="$(REG_STATE_DIR="$T/explicit" HARNESS_SELFTEST=1 reg_state_dir)"
  [[ "$explicit" == "$T/explicit" ]] && pass "explicit REG_STATE_DIR still wins over the guard" \
    || fail "explicit REG_STATE_DIR ignored, got '$explicit'"
  local prod; prod="$(HARNESS_SELFTEST=0 reg_state_dir)"
  [[ "$prod" == "$HOME/.claude/state/estate" ]] && pass "production path unchanged when not self-testing" \
    || fail "production path wrong: '$prod'"
  export REG_STATE_DIR="$SAVED"

  echo "Scenario 9: sandbox integrity -- DELTA on the real registrations dir, not its absence"
  local real_dir="$HOME/.claude/state/estate/registrations"
  local before_n=0 after_n=0
  [[ -d "$real_dir" ]] && before_n="$(find "$real_dir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  ( unset REG_STATE_DIR; HARNESS_SELFTEST=1 reg_register selftest-marker /tmp/x session/x >/dev/null 2>&1 )
  [[ -d "$real_dir" ]] && after_n="$(find "$real_dir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$before_n" == "$after_n" ]] && pass "real registrations dir unchanged by this self-test ($before_n -> $after_n)" \
    || fail "SANDBOX ESCAPE: real registrations dir changed ($before_n -> $after_n)"

  echo "Scenario 10: reg_has_any_record covers OPEN, CLOSED, and NEVER-registered"
  reg_register wt-four "$T/wt-four" session/wt-four >/dev/null
  reg_has_any_record wt-four && pass "reg_has_any_record true for an OPEN registration" || fail "expected true (open)"
  reg_close wt-four "removed"
  reg_has_any_record wt-four && pass "reg_has_any_record true for a CLOSED registration" || fail "expected true (closed)"
  reg_has_any_record never-ever-registered && fail "reg_has_any_record true for a slug with no record at all" \
    || pass "reg_has_any_record false when neither an open nor a closed record exists"

  rm -rf "$T"
  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

# GATED ON BEING EXECUTED, NOT SOURCED (same discipline as admission-lib.sh --
# a sourced lib that dispatches on "$1" would inherit the caller's positionals).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) _reg_self_test ;;
  esac
fi
