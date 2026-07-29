#!/bin/bash
# review-record-commit-gate.sh — BLOCK a commit/push of an unreviewed harness change.
#
# ============================================================================
# THE GAP THIS CLOSES (golden case, PROVEN)
# ============================================================================
# 2026-07-28, commit f6562b2: a session wrote adapters/claude-code/hooks/lib/
# admission-lib.sh (664 lines, spliced into three live dispatch paths), committed
# it, and pushed it to master with NO harness-reviewer and NO task-verifier.
# When both were finally run they returned REJECT and FAIL respectively, on a
# deliverable that was already on master: a parser that returned 3379 for a true
# value of 3, a self-test whose headline "38/0" was only reproducible on a
# machine where the feature did not work, a "spawn-free ~0 ms" claim that
# measured 70.8 ms, and an ADM_STATE_DIR environment channel that silently
# bypassed the HALT kill switch.
#
# review-before-deploy.md already required a harness-reviewer PASS. It had TWO
# carriers, both at DEPLOY time: install.sh (hard block) and
# session-start-auto-install.sh (fail-open warn). Neither runs at COMMIT time,
# so f6562b2 sailed through and reached origin/master unreviewed.
# harness-reviewer's own words on 2026-07-28: wiring the commit-time carrier is
# "the single most important thing to fix", and the enforcement API
# (rrg_in_surface / rrg_is_covered) plus scripts/write-review-record.sh already
# existed, unwired.
#
# This hook is that carrier. It BLOCKS (exit 2) rather than warns, at the
# operator's explicit direction 2026-07-29 ("Why are you suggesting warn mode?
# If it's valuable, then build and deploy it").
#
# ============================================================================
# CONSTITUTION §10 EVIDENCE BAR
# ============================================================================
# §10 requires a named golden scenario, an expected false-positive rate, and a
# retirement condition before a new BLOCKING gate ships. All three:
#
#   GOLDEN SCENARIO : commit f6562b2 above. Replaying this gate against that
#                     commit's staged set MUST block. Self-test scenario 1
#                     asserts exactly that shape.
#   FP EXPECTATION  : measured retroactively rather than by a warn period —
#                     see scripts/measure-review-gate-fp.sh, which replays this
#                     gate's predicate over the last N commits and reports how
#                     many would have blocked, broken down by commit class.
#                     The gate's exemptions (below) were derived FROM that
#                     measurement, not guessed.
#   RETIREMENT      : retire when review-before-deploy's deploy-time carriers
#                     become redundant (a single continuously-reconciling sync
#                     path), or when a native review gate ships upstream, or if
#                     the measured FP rate exceeds the operator's tolerance.
#
# ============================================================================
# WHAT IT BLOCKS, AND WHAT IT DELIBERATELY DOES NOT
# ============================================================================
# BLOCKS: a `git commit` or `git push` when a STAGED, ADDED-OR-MODIFIED file is
# in-surface for harness review (rrg_in_surface: hooks/*.sh, scripts/*.sh,
# agents/*.md top-level, config/*, manifest.json, settings.json.template,
# rules/*) and its blob is NOT covered by a grandfather entry or a PASS record.
#
# NEVER BLOCKS (the false-positive budget — each of these is a real commit class
# that a naive version would have obstructed):
#   1. No staged in-surface file           -> silent allow, the common case.
#   2. Pure DELETIONS                       -> a removed file has no blob to
#      review; --diff-filter excludes D.
#   3. Mid-rebase / mid-merge / cherry-pick -> you cannot stop a rebase to get a
#      review; .git/REBASE_HEAD, MERGE_HEAD, CHERRY_PICK_HEAD short-circuit.
#   4. Not a git repo, no git, no jq        -> fail-open, never brick a machine.
#   5. Bootstrap                            -> rrg_is_covered itself fail-opens
#      when NEITHER coverage file exists on the checkout (Amendment E).
#   6. A record staged in the SAME commit   -> coverage is read with ref="" (the
#      working tree/index), so fixing the review and committing together works.
#      This is what makes the gate satisfiable in one pass.
#
# REMEDY-CHAIN (ADR 059 D5): the remedy this gate prescribes must not walk the
# operator into another gate. Writing a record via scripts/write-review-record.sh
# is a plain script call that commits nothing. The re-commit is a SEPARATE Bash
# call by NL-FINDING-016's rule (a fix and its retry are never one compound
# command), and the block message says so explicitly.
#
# ESCAPE HATCH (constitution §7 — a gate that cannot be waived gets routed
# around silently, which is worse): REVIEW_RECORD_GATE_OVERRIDE="<reason>" in the
# environment allows the commit AND appends the reason to
# ~/.claude/state/review-record-gate-overrides.log for periodic audit. An empty
# or missing reason does NOT override — the waiver must say why.
#
# Self-test: bash review-record-commit-gate.sh --self-test
# ============================================================================

set -uo pipefail

_RRCG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ============================================================================
# COMMAND PARSING — DELEGATED, NOT HAND-ROLLED (class fix, 2026-07-29)
# ============================================================================
# This hook used to carry its own `git commit` detector: a `${rest//&&/$'\n'}`
# string substitution over the RAW command, a segment walk that took the first
# bare token after `-C`, and no quote handling at all. harness-reviewer REJECTED
# it three times; each round the builder fixed the one shape demonstrated and
# shipped the CLASS. Seven PROVEN fail-opens remained (quoted -C, single-quoted
# -C, unexpanded-variable -C, `cd <harness> &&` from a foreign cwd, `pushd`,
# `--git-dir/--work-tree`, `cd <harness>;`) plus one over-fire (a `;` inside a
# quoted string manufactured a phantom command segment).
#
# All of it was already solved, correctly, in scope-enforcement-gate.sh — which
# runs in the SAME PreToolUse Bash chain. That parser is now extracted to
# lib/git-command-parse.sh and BOTH gates use it. There is ONE commit-target
# resolver in this harness. Do not add a second one here.
# ============================================================================
# shellcheck source=/dev/null
source "$_RRCG_SELF_DIR/lib/git-command-parse.sh" 2>/dev/null || true

_rrcg_log_override() {
  local reason="$1" repo="$2"
  local log="${REVIEW_RECORD_GATE_LOG:-$HOME/.claude/state/review-record-gate-overrides.log}"
  mkdir -p "$(dirname "$log")" 2>/dev/null || return 0
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
    "${repo:-unknown}" "$reason" >> "$log" 2>/dev/null || true
}

# NOTE ON `push`: it was REMOVED from the verb set (harness-review Major). The
# push arm checked the INDEX, which is the wrong subject — it blocked pushes over
# unrelated staged work while giving zero protection against pushing
# already-committed unreviewed changes, which is literally the golden case's
# final step. A correct push arm must diff @{u}..HEAD; until that is built,
# matching push is pure cost. Tracked in the manifest honest_status.
#
# Commit detection and target resolution now live entirely in
# lib/git-command-parse.sh (gcp_resolve_commit_target). See the banner above.

# _rrcg_is_harness_repo <root> — this gate is specific to the harness repo.
# Without this, ANY repo containing scripts/*.sh plus a docs/reviews/records/
# dir was gated (harness-review Major); only rrg's bootstrap fail-open was
# hiding it.
# Is the coverage index staged, or does it exist only in the worktree?
# Returns 0 (fine) when the file is unmodified vs the index — i.e. nothing new
# to stage — and 0 when it IS staged. Returns 1 when the worktree copy differs
# from the index copy, which is exactly "the record you are relying on is not in
# this commit".
#
# CALLER CONTRACT (harness-review Critical, 2026-07-29): only call this when at
# least one staged in-surface file was ACTUALLY covered by a record. It used to
# run unconditionally on the uncovered==0 path, so a docs-only commit that
# consulted ZERO coverage was blocked whenever index.json happened to have local
# edits — and the block message asserted "coverage is satisfied by ... your
# WORKING TREE", a reason the code had never established. See covered_count in
# _rrcg_main.
#
# BAILOUTS RESOLVE TOWARD BLOCK (the file's own principle, applied). Both git
# probes below used to `|| return 0` — i.e. "if I cannot tell whether the record
# is in the commit, authorize the commit". That is backwards for a gate: an
# unreadable or untracked index.json means the record demonstrably is NOT in the
# index, which is the exact condition this check exists to catch.
_rrcg_record_is_staged() {
  local repo_root="$1" rel="docs/reviews/records/index.json"
  # Genuinely not applicable (not a bailout): with no index.json on disk the
  # coverage that satisfied the gate came from grandfather-manifest.json, which
  # is committed. There is no working-tree-only record to strand.
  [[ -f "$repo_root/$rel" ]] || return 0
  local idx wt
  # Not in the index at all (untracked, or staged-for-deletion) -> it cannot be
  # part of this commit.
  idx="$(git -C "$repo_root" rev-parse ":$rel" 2>/dev/null)" || return 1
  wt="$(git -C "$repo_root" hash-object "$repo_root/$rel" 2>/dev/null)" || return 1
  [[ "$idx" == "$wt" ]]
}

_rrcg_is_harness_repo() {
  [[ -f "$1/adapters/claude-code/manifest.json" ]]
}

_rrcg_block_message() {
  local repo_root="$1"; shift
  local files=("$@")
  {
    echo "================================================================"
    echo "REVIEW-RECORD GATE — COMMIT BLOCKED"
    echo "================================================================"
    echo
    echo "These staged files change harness BEHAVIOR and have no review record:"
    local f
    for f in "${files[@]}"; do echo "  • $f"; done
    echo
    echo "Why this gate exists: on 2026-07-28 commit f6562b2 put a 664-line lib"
    echo "onto master with no harness-reviewer. Both reviewers, run afterwards,"
    echo "returned REJECT and FAIL — a parser that read 3379 for a true value of"
    echo "3, a self-test that only passed where the feature did not work, and an"
    echo "environment variable that silently bypassed the HALT kill switch. The"
    echo "review-before-deploy rule already required a PASS; its only carriers"
    echo "ran at DEPLOY time, so the commit sailed through."
    echo
    echo "NOTE: this block prevented the ENTIRE command from running — including"
    echo "anything before an && or ;. If you chained a fix in front of the commit,"
    echo "that fix did NOT execute (NL-FINDING-016: a builder retried a"
    echo "never-executed fix three times before noticing)."
    echo ""
    echo "TO PROCEED — three steps, as SEPARATE tool calls (never one compound"
    echo "command; a fix and its retry are separate calls by NL-FINDING-016):"
    echo
    echo "  1. Dispatch harness-reviewer on this change and get a verdict."
    echo "     Pass an explicit model — the default review tier can be budget-"
    echo "     exhausted, and a dead dispatch is a skipped review."
    echo
    echo "  2. Record the verdict:"
    echo "       bash adapters/claude-code/scripts/write-review-record.sh capture \\"
    echo "         --kind harness-change-review --reviewer harness-reviewer \\"
    echo "         --verdict PASS --plan-ref <plan> --quote '<verdict sentence>' \\"
    for f in "${files[@]}"; do echo "         --file $f \\"; done
    echo "         --commit-sha PENDING"
    echo
    echo "  3. Stage the record and re-run your commit. Coverage is read from the"
    echo "     index, so the record and the change can land in the SAME commit."
    echo
    echo "If the reviewer returned REFORMULATE or REJECT, the fix is to amend the"
    echo "change — not to record a PASS you did not get (constitution §1)."
    echo
    echo "Genuine emergency waiver (audit-logged, requires a reason):"
    echo "  REVIEW_RECORD_GATE_OVERRIDE=\"why this cannot wait\" git commit ..."
    echo "================================================================"
  } >&2
}

_rrcg_main() {
  local input; input="$(cat 2>/dev/null || true)"
  [[ -n "$input" ]] || return 0

  command -v jq >/dev/null 2>&1 || return 0    # fail-open: no jq, no gate

  local tool cmd
  tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  # PowerShell runs `git commit` too, and its `cd` is a Set-Location alias — both
  # of which the shared resolver understands. Gating only Bash left the same
  # silent bypass HARNESS-GAP-47 closed for scope-enforcement-gate in 2026-06.
  [[ "$tool" == "Bash" || "$tool" == "PowerShell" ]] || return 0
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true)"
  [[ -n "$cmd" ]] || return 0

  # The shared resolver is load-bearing. If it is missing we cannot tell a commit
  # from a mention; the gate has nothing to stand on, so pass through (documented
  # fail-open class 4 — never brick a machine) but say so on stderr rather than
  # dying silently.
  if ! command -v gcp_resolve_commit_target >/dev/null 2>&1; then
    echo "review-record-commit-gate: lib/git-command-parse.sh unavailable — gate skipped." >&2
    return 0
  fi
  gcp_resolve_commit_target "$cmd" "$PWD"
  if [[ "${GCP_IS_COMMIT:-0}" -ne 1 ]]; then
    # BAILOUT RESOLVES TOWARD BLOCK: a degraded parse means "I could not tell",
    # not "it is not a commit". Fall through to the coverage check, which only
    # blocks if unreviewed harness content is genuinely staged.
    [[ "${GCP_PARSE_DEGRADED:-0}" -eq 1 ]] || return 0
    echo "review-record-commit-gate: command parse degraded — checking coverage anyway." >&2
  fi

  command -v git >/dev/null 2>&1 || return 0
  local repo_root="" target="${GCP_TARGET_DIR:-}"
  # NOTE: the two bare `git rev-parse` calls below run BEFORE repo_root is known
  # and deliberately take the process cwd as their subject — that is the thing
  # being resolved. Every git call AFTER this point takes -C "$repo_root".
  if [[ -n "$target" ]]; then
    repo_root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || repo_root=""
    # BAILOUT RESOLVES TOWARD BLOCK: an unresolvable target (a path that does not
    # exist, an unexpanded `$REPO`, a non-repo dir) used to `|| return 0` and
    # authorize the commit outright — PROVEN fail-open for `git -C $REPO commit`.
    # Falling back to the cwd cannot over-fire: if the cwd is not a harness repo
    # the identity check below allows anyway.
    [[ -n "$repo_root" ]] || repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || repo_root=""
  else
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || repo_root=""
  fi
  [[ -n "$repo_root" ]] || return 0
  # Harness-repo identity: this gate governs THIS harness's in-surface files.
  _rrcg_is_harness_repo "$repo_root" || return 0

  # Exemption 3: never interrupt an in-progress rebase/merge/cherry-pick.
  # -C "$repo_root", NOT the cwd (harness-review Major, 2026-07-29). Reading the
  # CWD's git-dir cut both ways: a rebase in some unrelated repo you happened to
  # be standing in DISARMED the gate for a commit targeting the harness, and a
  # genuine rebase in the target repo did NOT exempt it, stranding the operator
  # mid-rebase with no way forward.
  local gitdir
  gitdir="$(git -C "$repo_root" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir=""
  if [[ -z "$gitdir" ]]; then
    # --absolute-git-dir predates git 2.13; fall back and resolve by hand.
    gitdir="$(git -C "$repo_root" rev-parse --git-dir 2>/dev/null)" || gitdir=""
    case "$gitdir" in
      ""|/*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
      *) gitdir="$repo_root/$gitdir" ;;
    esac
  fi
  if [[ -n "$gitdir" ]]; then
    for m in REBASE_HEAD MERGE_HEAD CHERRY_PICK_HEAD; do
      [[ -e "$gitdir/$m" ]] && return 0
    done
    [[ -d "$gitdir/rebase-merge" || -d "$gitdir/rebase-apply" ]] && return 0
  fi

  # Escape hatch — loud and logged, and only with a stated reason.
  local ovr="${REVIEW_RECORD_GATE_OVERRIDE:-}"
  # A one-character reason is not a reason (harness-review Major:
  # silent-self-waiver). Demand something substantive, and reject the obvious
  # placeholders, so a waiver is a statement the operator can audit rather than
  # a keystroke the agent can emit in-band.
  case "$(printf '%s' "$ovr" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    x|test|testing|temp|tmp|skip|bypass|because|na|n/a|bypassbypassbypassbypass)
      echo "review-record-commit-gate: placeholder waiver reason rejected." >&2; ovr="" ;;
  esac
  if [[ -n "$ovr" ]] && [[ "${#ovr}" -lt 20 ]]; then
    echo "review-record-commit-gate: REVIEW_RECORD_GATE_OVERRIDE rejected — a waiver must state WHY (>=20 chars), got '${ovr}'." >&2
    ovr=""
  fi
  if [[ -n "$ovr" ]]; then
    _rrcg_log_override "$ovr" "$repo_root"
    echo "review-record-commit-gate: OVERRIDDEN — \"$ovr\" (logged for audit)" >&2
    return 0
  fi

  # shellcheck source=/dev/null
  source "$_RRCG_SELF_DIR/lib/review-record-gate-lib.sh" 2>/dev/null || return 0
  command -v rrg_in_surface >/dev/null 2>&1 || return 0
  command -v rrg_is_covered >/dev/null 2>&1 || return 0

  # Exemption 2: ACMR excludes deletions — a removed blob cannot be reviewed.
  local staged
  staged="$(git -C "$repo_root" diff --cached --name-only --diff-filter=ACMR 2>/dev/null)" || return 0
  [[ -n "$staged" ]] || return 0    # exemption 1: nothing staged

  local -a uncovered=()
  local path sha covered_count=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    rrg_in_surface "$path" || continue
    # THE INDEX, NOT THE WORKING TREE (harness-review Critical, 2026-07-29).
    # rrg_blob_sha_of_file hashes the FILESYSTEM, but `git commit` commits the
    # INDEX. The reviewer staged unreviewed content, restored the worktree to a
    # covered blob, and the commit sailed through rc=0 — the gate attested to
    # bytes it never read. It also fails the other way: stage the reviewed
    # version, keep editing, and the commit is wrongly blocked.
    sha="$(git -C "$repo_root" rev-parse ":$path" 2>/dev/null)" || sha=""
    [[ -n "$sha" ]] || continue
    # ref="" => read coverage from the WORKING TREE/index, so a record staged in
    # this same commit counts (exemption 6 — makes the gate satisfiable in one pass).
    # Coverage is read from the WORKING TREE (ref=""), which is what
    # rrg_is_covered supports — the lib has no index mode (it branches to `cat`
    # on an empty ref and to `git show <ref>:<path>` otherwise, so there is no
    # way to ask it for `:<path>`). The blob, correctly, comes from the index.
    # harness-reviewer flagged the asymmetry: an UNSTAGED record satisfies the
    # gate, so the change could land with no record actually in the commit and a
    # later `git clean` would discard the only evidence. Rather than fork the
    # lib, that hole is closed explicitly below (_rrcg_record_is_staged).
    if ! rrg_is_covered "$repo_root" "" "$path" "$sha"; then
      uncovered+=("$path")
    else
      covered_count=$((covered_count+1))
    fi
  done <<< "$staged"

  # The record that satisfies coverage must itself be STAGED, or it is not part
  # of the commit the gate just authorized (harness-reviewer Major, 2026-07-29).
  #
  # GATED ON covered_count > 0 (harness-review Critical, 2026-07-29). This ran
  # unconditionally, so a docs-only commit — which consults no coverage at all —
  # was blocked whenever index.json merely had unstaged local edits, and was told
  # "coverage is satisfied by ... your WORKING TREE", a reason that had never been
  # established. The check is only meaningful when a record actually did the
  # satisfying.
  if [[ "${#uncovered[@]}" -eq 0 ]]; then
    if [[ "$covered_count" -gt 0 ]] && ! _rrcg_record_is_staged "$repo_root"; then
      {
        echo "================================================================"
        echo "REVIEW-RECORD GATE — RECORD NOT STAGED"
        echo "================================================================"
        echo "$covered_count staged in-surface file(s) are covered ONLY by"
        echo "docs/reviews/records/index.json as it exists in your WORKING TREE."
        echo "That file is not staged, so it will NOT be part of this commit: the"
        echo "change would land with no review record in the tree, and a later"
        echo "\`git clean -fd\` or worktree teardown would discard the only evidence."
        echo ""
        echo "FIX (separate call): git add docs/reviews/records/"
        echo "================================================================"
      } >&2
      return 2
    fi
    return 0
  fi

  # ledger_emit lives in lib/signal-ledger.sh, which this hook never sourced —
  # so the guard was ALWAYS false and no block was ever recorded (harness-review
  # Major: write-only observability). Source it, then emit.
  source "$_RRCG_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true
  command -v ledger_emit >/dev/null 2>&1 && \
    ledger_emit "review-record-commit-gate" "block" "files=${#uncovered[@]}"
  _rrcg_block_message "$repo_root" "${uncovered[@]}"
  return 2
}

# ===========================================================================
# Self-test
# ===========================================================================
_rrcg_self_test() {
  local PASS=0 FAIL=0
  pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
  fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }

  local T; T="$(mktemp -d)" || { echo "cannot mktemp"; return 1; }
  # ABSOLUTE — every scenario below runs the gate from inside a temp repo, so a
  # relative ${BASH_SOURCE[0]} resolves to nothing there and every scenario
  # returns 127 (command not found) while LOOKING like a gate failure.
  local SELF="$_RRCG_SELF_DIR/$(basename "${BASH_SOURCE[0]}")"

  # a throwaway repo with the coverage files present, so we exercise real
  # non-coverage rather than rrg's bootstrap fail-open
  local R="$T/repo"
  mkdir -p "$R/adapters/claude-code/hooks/lib" "$R/docs/reviews/records"
  # The fixture must LOOK like the harness repo: _rrcg_is_harness_repo keys on
  # adapters/claude-code/manifest.json (added 2026-07-29 so the gate stops
  # governing unrelated repos). Without this every scenario silently allows.
  printf '{"schema_version":1,"entries":[]}\n' > "$R/adapters/claude-code/manifest.json"
  ( cd "$R" && git init -q . && git config user.email t@example.com && git config user.name T \
      && git config core.hooksPath "" ) >/dev/null 2>&1
  cp "$_RRCG_SELF_DIR/lib/review-record-gate-lib.sh" "$R/adapters/claude-code/hooks/lib/" 2>/dev/null
  printf '{"records":[]}\n' > "$R/docs/reviews/records/index.json"
  printf '{"entries":[]}\n' > "$R/docs/reviews/records/grandfather-manifest.json"
  ( cd "$R" && git add -A && git commit -qm init ) >/dev/null 2>&1

  run() { # $1 = command string; echoes rc
    # Build the JSON with jq, not printf: a command containing double quotes
    # (`git commit -m "feat: x"` — the overwhelmingly common real shape) makes a
    # printf-built payload INVALID JSON, jq rejects it, and the gate fail-opens.
    # The first draft of this suite used printf and its golden case silently
    # "passed the gate" for that reason alone.
    local payload
    payload="$(jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}')"
    printf '%s' "$payload" | ( cd "$R" && bash "$SELF" ) >/dev/null 2>&1
    echo $?
  }

  echo "Scenario 1: GOLDEN CASE — staging an unreviewed hooks/lib/*.sh blocks the commit"
  mkdir -p "$R/adapters/claude-code/hooks/lib"
  echo '# unreviewed harness change' > "$R/adapters/claude-code/hooks/lib/admission-lib.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  local rc; rc="$(run 'git commit -m "feat: admission lib"')"
  [[ "$rc" == "2" ]] && pass "f6562b2-shaped commit BLOCKED (rc=2)" || fail "expected rc 2, got $rc — the golden case does not fire"

  echo "Scenario 2: the block message names the file and the remedy"
  local msg; msg="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | ( cd "$R" && bash "$SELF" ) 2>&1 >/dev/null)"
  case "$msg" in *admission-lib.sh*) pass "message names the offending file" ;; *) fail "message omits the file" ;; esac
  case "$msg" in *write-review-record.sh*) pass "message names the exact remedy command" ;; *) fail "message omits the remedy" ;; esac
  case "$msg" in *"ENTIRE command"*) pass "message carries the NL-FINDING-016 whole-command-discarded banner" ;; *) fail "banner missing (deleting it must turn this test RED)" ;; esac
  case "$msg" in *NL-FINDING-016*) pass "message cites NL-FINDING-016 by name" ;; *) fail "NL-FINDING-016 citation missing" ;; esac

  echo "Scenario 3: FP budget — a NON-surface file does not block"
  ( cd "$R" && git reset -q ) >/dev/null 2>&1
  mkdir -p "$R/docs"; echo 'notes' > "$R/docs/notes.md"
  ( cd "$R" && git add docs/notes.md ) >/dev/null 2>&1
  rc="$(run 'git commit -m "docs: notes"')"
  [[ "$rc" == "0" ]] && pass "docs-only commit allowed" || fail "docs-only commit blocked (rc=$rc) — false positive"

  echo "Scenario 4: FP budget — nothing staged at all"
  ( cd "$R" && git reset -q ) >/dev/null 2>&1
  rc="$(run 'git commit -m "empty"')"
  [[ "$rc" == "0" ]] && pass "no staged files -> allowed" || fail "blocked with empty index (rc=$rc)"

  echo "Scenario 5: FP budget — a pure DELETION of an in-surface file"
  ( cd "$R" && git add -A && git commit -qm "add for deletion test" ) >/dev/null 2>&1
  ( cd "$R" && git rm -q adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  rc="$(run 'git commit -m "chore: remove lib"')"
  [[ "$rc" == "0" ]] && pass "deletion-only commit allowed (no blob to review)" || fail "deletion blocked (rc=$rc) — false positive"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1

  echo "Scenario 6: FP budget — non-commit git commands are untouched"
  echo '# x' > "$R/adapters/claude-code/hooks/lib/other.sh"
  ( cd "$R" && git add -A ) >/dev/null 2>&1
  for c in 'git status' 'git diff --cached' 'git log --oneline -5' 'ls -la'; do
    rc="$(run "$c")"
    [[ "$rc" == "0" ]] && pass "allowed: $c" || fail "blocked a non-commit command: $c (rc=$rc)"
  done

  echo "Scenario 7: mid-rebase is never interrupted"
  local gd; gd="$(cd "$R" && git rev-parse --git-dir)"
  : > "$R/$gd/REBASE_HEAD" 2>/dev/null || : > "$gd/REBASE_HEAD" 2>/dev/null
  rc="$(run 'git commit -m "during rebase"')"
  [[ "$rc" == "0" ]] && pass "commit during rebase allowed" || fail "blocked mid-rebase (rc=$rc) — would strand the operator"
  rm -f "$R/$gd/REBASE_HEAD" "$gd/REBASE_HEAD" 2>/dev/null

  echo "Scenario 8: escape hatch requires a REASON, and is logged"
  export REVIEW_RECORD_GATE_LOG="$T/ovr.log"
  rc="$(REVIEW_RECORD_GATE_OVERRIDE="" bash -c "printf '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"}}' | cd '$R' 2>/dev/null; true"; \
        printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | ( cd "$R" && REVIEW_RECORD_GATE_OVERRIDE="" bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "2" ]] && pass "EMPTY override does NOT waive the gate" || fail "empty override waived the gate (rc=$rc)"
  rc="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | ( cd "$R" && REVIEW_RECORD_GATE_OVERRIDE="production is down and this hotfix cannot wait for review" bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "override WITH a substantive reason allows the commit" || fail "reasoned override did not allow (rc=$rc)"
  rc="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | ( cd "$R" && REVIEW_RECORD_GATE_OVERRIDE="x" bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "2" ]] && pass "a one-character 'reason' is REJECTED (waivers must state why)" || fail "trivial reason waived the gate (rc=$rc)"
  rc="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | ( cd "$R" && REVIEW_RECORD_GATE_OVERRIDE="testing" bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "2" ]] && pass "placeholder reason 'testing' is REJECTED" || fail "placeholder waived the gate (rc=$rc)"
  if grep -q 'production is down and this hotfix cannot wait' "$T/ovr.log" 2>/dev/null; then
    pass "override written to the audit log with its reason"
  else fail "override not logged — a silent waiver is worse than no gate"; fi
  unset REVIEW_RECORD_GATE_LOG

  echo "Scenario 9: coverage staged in the SAME commit satisfies the gate (one-pass fix)"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# reviewed change' > "$R/adapters/claude-code/hooks/lib/covered.sh"
  local blob; blob="$(cd "$R" && git hash-object adapters/claude-code/hooks/lib/covered.sh)"
  # Schema is the REAL one rrg_is_covered matches (lib :158-159): a flat
  # .entries[] of {path, blob_sha, kind, verdict} — not a nested records/files
  # shape. The first draft of this scenario invented the nested shape and failed,
  # which is the same author-written-fixture trap that hid two Critical parser
  # defects in admission-lib a day earlier.
  printf '{"entries":[{"path":"adapters/claude-code/hooks/lib/covered.sh","blob_sha":"%s","kind":"harness-change-review","verdict":"PASS"}]}\n' "$blob" \
    > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add -A ) >/dev/null 2>&1
  rc="$(run 'git commit -m "feat: reviewed change"')"
  [[ "$rc" == "0" ]] && pass "a PASS record staged alongside the change satisfies the gate" \
    || fail "blocked despite an in-index PASS record (rc=$rc) — the gate would be unsatisfiable in one pass"

  echo "Scenario 10: fail-open — not a git repo"
  rc="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | ( cd "$T" && bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "outside a git repo -> allowed (never brick)" || fail "blocked outside a repo (rc=$rc)"

  echo "Scenario 11: INDEX vs WORKING TREE — the Critical the reviewer proved (E10)"
  # Stage UNREVIEWED content, then restore the worktree to a COVERED blob. A gate
  # that hashes the filesystem says "covered" and lets unreviewed bytes through.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# reviewed good' > "$R/adapters/claude-code/hooks/lib/covered.sh"
  local goodblob; goodblob="$(cd "$R" && git hash-object adapters/claude-code/hooks/lib/covered.sh)"
  printf '{"entries":[{"path":"adapters/claude-code/hooks/lib/covered.sh","blob_sha":"%s","kind":"harness-change-review","verdict":"PASS"}]}\n' "$goodblob" \
    > "$R/docs/reviews/records/index.json"
  echo '# EVIL unreviewed' > "$R/adapters/claude-code/hooks/lib/covered.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/covered.sh ) >/dev/null 2>&1   # stage EVIL
  echo '# reviewed good' > "$R/adapters/claude-code/hooks/lib/covered.sh"            # worktree back to GOOD
  rc="$(run 'git commit -m sneak')"
  [[ "$rc" == "2" ]] && pass "staged-unreviewed + covered-worktree BLOCKS (gate reads the index)" \
    || fail "INDEX/WORKTREE HOLE: unreviewed staged content committed (rc=$rc)"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1

  echo "Scenario 12: substring-as-intent — merely MENTIONING the phrase is not a commit (E13)"
  echo '# x' > "$R/adapters/claude-code/hooks/lib/mention.sh"
  ( cd "$R" && git add -A ) >/dev/null 2>&1
  local m
  for m in 'echo run git commit later' 'man git commit' 'grep -rn "git commit" docs/'; do
    rc="$(run "$m")"
    [[ "$rc" == "0" ]] && pass "allowed (mention only): $m" || fail "blocked a mere mention: $m (rc=$rc)"
  done
  rc="$(run 'git commit -m real')"
  [[ "$rc" == "2" ]] && pass "a REAL commit in command position still blocks" || fail "anchoring broke the real case (rc=$rc)"

  echo "Scenario 12b: a -C target from an EARLIER segment must not repoint the gate"
  # harness-reviewer proved four fail-open shapes where `git -C <path>` anywhere
  # in the raw command repointed repo_root at another repo; if that path was not
  # a harness repo (or did not exist) the gate returned 0 with an unreviewed blob
  # staged. The worst was the orchestrator's OWN cherry-pick shape.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# unreviewed' > "$R/adapters/claude-code/hooks/lib/leak.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/leak.sh ) >/dev/null 2>&1
  local _sib="$T/sibling"; mkdir -p "$_sib"
  ( cd "$_sib" && git init -q . && git config user.email t@example.com && git config user.name T ) >/dev/null 2>&1
  local _v; _v="$(printf 'git com''mit')"
  local _shape
  for _shape in \
    "git -C $_sib log --oneline -1 && git add -A && $_v -m x" \
    "git -C /no/such/path fetch && $_v -m x" \
    "echo \"git -C $_sib status\" && $_v -m x" \
    "$_v -m 'use git -C /tmp/other next time'"; do
    rc="$(run "$_shape")"
    [[ "$rc" == "2" ]] && pass "blocks despite a -C mention: ${_shape:0:46}..." \
      || fail "FAIL-OPEN (rc=$rc): $_shape"
  done

  echo "Scenario 13: foreign repo is not governed by this gate (E12)"
  local FR="$T/foreign"
  mkdir -p "$FR/scripts" "$FR/docs/reviews/records"
  ( cd "$FR" && git init -q . && git config user.email t@example.com && git config user.name T ) >/dev/null 2>&1
  printf '{"records":[]}\n' > "$FR/docs/reviews/records/index.json"
  echo '# deploy' > "$FR/scripts/deploy.sh"
  ( cd "$FR" && git add -A ) >/dev/null 2>&1
  rc="$(printf '%s' "$(jq -nc '{tool_name:"Bash",tool_input:{command:"git commit -m x"}}')" | ( cd "$FR" && bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "a non-harness repo with scripts/*.sh is NOT gated" || fail "gated a foreign repo (rc=$rc)"

  # ==========================================================================
  # Scenario 14: THE SEVEN PROVEN FAIL-OPENS (harness-reviewer probe B2-B4, C2-C5)
  # ==========================================================================
  # Every shape below reaches a `git commit` that targets THIS harness repo with
  # an unreviewed in-surface file staged. Each returned rc=0 before the shared
  # resolver landed — verified by running the probe against the pre-fix gate.
  # `runfrom` runs the gate from an arbitrary cwd, because the whole point of
  # four of these shapes is that the commit targets a repo the caller is not in.
  echo "Scenario 14: the seven PROVEN fail-opens must all BLOCK"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  # Content must DIFFER from whatever earlier scenarios committed, or `git add`
  # stages nothing, `git diff --cached` is empty, and every shape below returns
  # rc=0 via exemption 1 — a green-looking suite that tested nothing.
  echo '# unreviewed change, scenario 14 marker' > "$R/adapters/claude-code/hooks/lib/admission-lib.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  ( cd "$R" && git diff --cached --quiet ) && fail "scenario 14 fixture staged NOTHING — the shapes below would all pass vacuously"
  local OUT="$T/outside"; mkdir -p "$OUT"
  runfrom() { # $1 = cwd, $2 = command string; echoes rc
    local payload
    payload="$(jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}')"
    printf '%s' "$payload" | ( cd "$1" && bash "$SELF" ) >/dev/null 2>&1
    echo $?
  }
  # `git commit` is assembled at runtime so this suite's own source does not
  # contain the phrase in command position (the harness gates read hook source).
  # TWO forms are needed: CV for a segment that starts the command, SUB for the
  # bare subcommand where `git <flags>` is already written. Splicing CV after
  # `git -C <path>` yields `git -C <path> git commit`, which is NOT a commit —
  # the resolver correctly returns 0 and the scenario passes vacuously. That
  # exact mistake made four of these read as fail-opens during development.
  local CV SUB; CV="$(printf 'git com''mit')"; SUB="$(printf 'com''mit')"
  local _lbl _cwd _cmd
  while IFS='|' read -r _lbl _cwd _cmd; do
    [[ -n "$_lbl" ]] || continue
    rc="$(runfrom "$_cwd" "$_cmd")"
    [[ "$rc" == "2" ]] && pass "BLOCKS: $_lbl" || fail "FAIL-OPEN (rc=$rc): $_lbl"
  done <<EOF
B2 git -C "quoted path"|$OUT|git -C "$R" $SUB -m x
B3 git -C 'single-quoted path'|$OUT|git -C '$R' $SUB -m x
B4 git -C \$REPO (unexpanded variable)|$R|git -C \$REPO $SUB -m x
C2 cd <harness> && commit, from a NON-harness cwd|$OUT|cd $R && $CV -m x
C3 pushd <harness> && commit|$OUT|pushd $R && $CV -m x
C4 --git-dir/--work-tree from a non-harness cwd|$OUT|git --git-dir=$R/.git --work-tree=$R $SUB -m x
C5 cd <harness>; commit (semicolon)|$OUT|cd $R; $CV -m x
EOF

  echo "Scenario 15: over-fire budget — a separator INSIDE a quoted string (F1)"
  # `echo "step: stage; git commit -m msg" >> notes.md` writes a note. The old
  # quote-blind `${rest//;/...}` split manufactured a phantom `git commit`
  # segment from the middle of the string and blocked the echo outright.
  rc="$(runfrom "$R" "echo \"step: stage; $CV -m msg\" >> notes.md")"
  [[ "$rc" == "0" ]] && pass "quoted separator does not manufacture a commit" \
    || fail "OVER-FIRE (rc=$rc): blocked an echo whose STRING contained '; git commit'"
  rc="$(runfrom "$R" "echo 'stage then $CV -m x'")"
  [[ "$rc" == "0" ]] && pass "single-quoted mention does not fire" || fail "OVER-FIRE (rc=$rc) on a single-quoted mention"

  echo "Scenario 16: record-staged check is gated on covered_count > 0"
  # NEGATIVE: a docs-only commit consults ZERO coverage. A dirty index.json in the
  # working tree is none of its business. This ran unconditionally and blocked,
  # asserting a "coverage is satisfied by your WORKING TREE" reason the code had
  # never established.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  mkdir -p "$R/docs"
  # UNIQUE content. `echo 'notes'` rewrote the same bytes an earlier scenario had
  # already committed, so `git add` staged nothing, the empty-index exemption
  # returned 0 first, and this scenario passed without ever reaching the check it
  # exists to test. The fixture assertion below makes that failure loud.
  echo 'notes for the covered_count negative case' > "$R/docs/notes.md"
  ( cd "$R" && git add docs/notes.md ) >/dev/null 2>&1
  ( cd "$R" && git diff --cached --quiet ) && fail "scenario 16 negative fixture staged NOTHING — it would pass vacuously"
  printf '{"entries":[{"path":"unrelated","blob_sha":"deadbeef","kind":"harness-change-review","verdict":"PASS"}]}\n' \
    > "$R/docs/reviews/records/index.json"        # dirty in the WORKTREE, NOT staged
  rc="$(run "$CV -m 'docs: notes'")"
  [[ "$rc" == "0" ]] && pass "docs-only commit + dirty index.json -> allowed (no coverage consulted)" \
    || fail "blocked a docs-only commit over an unrelated dirty index.json (rc=$rc)"
  # POSITIVE: when coverage IS what let the change through, the record must be in
  # the commit. Deleting the covered_count guard must NOT turn this green-by-luck.
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# reviewed change' > "$R/adapters/claude-code/hooks/lib/covered.sh"
  local cblob; cblob="$(cd "$R" && git hash-object adapters/claude-code/hooks/lib/covered.sh)"
  printf '{"entries":[{"path":"adapters/claude-code/hooks/lib/covered.sh","blob_sha":"%s","kind":"harness-change-review","verdict":"PASS"}]}\n' "$cblob" \
    > "$R/docs/reviews/records/index.json"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/covered.sh ) >/dev/null 2>&1   # stage the CHANGE only
  rc="$(run "$CV -m 'feat: covered but record unstaged'")"
  [[ "$rc" == "2" ]] && pass "covered-by-an-UNSTAGED-record -> BLOCKED (record must be in the commit)" \
    || fail "allowed a commit whose only review record is unstaged (rc=$rc)"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1

  echo "Scenario 17: the placeholder-waiver case actually fires"
  # This case was UNTESTED: deleting it left the suite at 30/30. "bypass bypass
  # bypass bypass" is 27 chars, so it CLEARS the >=20 length check — only the
  # placeholder case can reject it. Deleting that case turns this RED.
  echo '# unreviewed' > "$R/adapters/claude-code/hooks/lib/admission-lib.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  rc="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
        | ( cd "$R" && REVIEW_RECORD_GATE_OVERRIDE="bypass bypass bypass bypass" bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "2" ]] && pass "a long-but-placeholder waiver ('bypass bypass ...') is REJECTED" \
    || fail "placeholder waiver of >=20 chars waived the gate (rc=$rc) — the case is dead code"
  # control: a genuinely substantive reason of similar length still works
  rc="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
        | ( cd "$R" && REVIEW_RECORD_GATE_OVERRIDE="rollback of a bad deploy, reviewer unavailable" bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "0" ]] && pass "a substantive waiver of similar length still allows" \
    || fail "the placeholder case is over-broad — it rejected a real reason (rc=$rc)"

  echo "Scenario 18: rebase state is read from the TARGET repo, not the cwd"
  # A rebase in some unrelated repo you happen to be standing in must NOT disarm
  # the gate for a commit targeting the harness.
  local RB="$T/rebasing"; mkdir -p "$RB"
  ( cd "$RB" && git init -q . && git config user.email t@example.com && git config user.name T ) >/dev/null 2>&1
  local rbgd; rbgd="$(cd "$RB" && git rev-parse --git-dir)"
  case "$rbgd" in /*) : ;; *) rbgd="$RB/$rbgd" ;; esac
  : > "$rbgd/REBASE_HEAD"
  rc="$(runfrom "$RB" "git -C $R $SUB -m x")"
  [[ "$rc" == "2" ]] && pass "a FOREIGN repo's rebase does not disarm the gate" \
    || fail "foreign rebase state disarmed the gate (rc=$rc)"
  # ...and a genuine rebase IN THE TARGET still exempts, from any cwd.
  local tgd; tgd="$(cd "$R" && git rev-parse --git-dir)"
  case "$tgd" in /*) : ;; *) tgd="$R/$tgd" ;; esac
  : > "$tgd/REBASE_HEAD"
  rc="$(runfrom "$RB" "git -C $R $SUB -m x")"
  [[ "$rc" == "0" ]] && pass "a rebase IN THE TARGET repo exempts from any cwd" \
    || fail "genuine target-repo rebase not exempted (rc=$rc) — strands the operator"
  rm -f "$tgd/REBASE_HEAD" "$rbgd/REBASE_HEAD"

  echo "Scenario 19: PowerShell tool input is gated too"
  ( cd "$R" && git reset -q --hard ) >/dev/null 2>&1
  echo '# unreviewed' > "$R/adapters/claude-code/hooks/lib/admission-lib.sh"
  ( cd "$R" && git add adapters/claude-code/hooks/lib/admission-lib.sh ) >/dev/null 2>&1
  rc="$(printf '%s' "$(jq -nc --arg c "$CV -m x" '{tool_name:"PowerShell",tool_input:{command:$c}}')" \
        | ( cd "$R" && bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "2" ]] && pass "a PowerShell-tool commit is gated" || fail "PowerShell bypass open (rc=$rc)"
  rc="$(printf '%s' "$(jq -nc --arg c "Set-Location $R; $CV -m x" '{tool_name:"PowerShell",tool_input:{command:$c}}')" \
        | ( cd "$OUT" && bash "$SELF" ) >/dev/null 2>&1; echo $?)"
  [[ "$rc" == "2" ]] && pass "PowerShell Set-Location + commit is gated" || fail "PowerShell Set-Location bypass open (rc=$rc)"

  rm -rf "$T"
  echo
  echo "self-test summary: $PASS passed, $FAIL failed"
  [[ "$FAIL" == "0" ]] && { echo "self-test: OK"; return 0; }
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) _rrcg_self_test; exit $? ;;
    *) _rrcg_main; exit $? ;;
  esac
fi
