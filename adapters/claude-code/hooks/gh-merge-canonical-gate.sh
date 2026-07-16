#!/bin/bash
# gh-merge-canonical-gate.sh — PreToolUse (Bash): BLOCK a `gh pr merge` / `gh api
# .../pulls/N/merge` whose RESOLVED target repo is the non-canonical work-org
# (`pt`) repo.
#
# WHY: decision 064 (docs/decisions/064-never-diverge-single-canonical-master.md,
# architecture-reviewed 2026-07-16, SOUND-WITH-AMENDMENTS). The neural-lace repo
# is dual-hosted (personal `origin` = canonical, work-org `pt` = mirror). A PR
# merged server-side on the pt repo lands on ITS master only — no local hook can
# observe it after the fact — and when both repos take server-side merges
# between reconciles, the masters truly diverge (2026-07-15: 14/10 split). This
# gate is the pre-emptive half: block the merge BEFORE it happens, on every
# harnessed machine, so a gate-synced session can never author a pt-side merge.
#
# HONEST STATUS (amendments A1-A4 — this is DEFENSE-IN-DEPTH, NOT the guarantee):
# server-side branch protection on pt/master (operator-only, access-control
# change) is the PRIMARY structural mechanism — it is the only layer that covers
# GitHub web-UI merges, CI, collaborators, and un-harnessed machines uniformly.
# This gate covers ONLY the gh-CLI merge path on a machine that has already
# synced this hook (a brand-new session on a machine that just deployed it is
# unprotected until its NEXT session start — the same deploy-lag class as other
# harness rollouts). Residual writers this gate does NOT cover: GitHub web-UI
# "Merge pull request", un-harnessed/external machines, CI/GitHub Actions,
# scheduled/cloud agents (Decision 011 — no PreToolUse), direct `git push pt
# master`. Only branch protection closes these.
#
# TARGET RESOLUTION (A4) — mirrors how `gh` itself resolves the current repo,
# entirely OFFLINE (no `gh api`/network call in the hook path, so a network
# hiccup can never turn into a false BLOCK of a legitimate personal-side merge):
#   1. An explicit repo in the command itself wins: `gh api repos/OWNER/REPO/
#      pulls/N/merge`, or an explicit `--repo`/`-R` flag on `gh pr merge`.
#   2. Else, the checkout's `gh repo set-default` state (`git config
#      remote.<name>.gh-resolved base` — the exact mechanism `gh repo
#      set-default` writes).
#   3. Else, a REMOTE HEURISTIC: the sole recognized (github.com-hosted) remote
#      is the default, matching gh's own resolution (an SSH host-ALIAS remote,
#      e.g. `pt` via `github-pt`, is not textually github.com-shaped and is NOT
#      a candidate here — exactly why `pt`'s IDENTITY, below, is read directly
#      from the `pt` remote by name rather than inferred from this heuristic).
#   4. If the heuristic finds zero or more-than-one candidate, the target is
#      AMBIGUOUS -> FAIL LOUD and BLOCK (never silently allow, and never
#      silently reinterpret ambiguity as "must be pt" either) — the message
#      teaches `--repo owner/name` or `gh repo set-default`.
#
# The `pt` repo's OWN identity is read from `git remote get-url pt` (FETCH url)
# AT RUNTIME — never a hardcoded org/repo name (hygiene denylist). If this
# checkout has no remote literally named `pt`, the gate does not apply here
# (fail OPEN — an unrelated repo elsewhere on the estate must never be blocked
# just because IT lacks the concept of a "pt" mirror).
#
# ALLOW when: not a Bash tool call; not a merge-shaped `gh` command; no `pt`
#   remote configured in this checkout; the resolved target != the `pt` repo.
# BLOCK (exit 2) when: the resolved target == the `pt` repo, OR the target is
#   genuinely ambiguous/unresolvable (a distinct, loud, teaching message).
# FAIL-OPEN (exit 0) ONLY on internal limitation (no jq / empty-or-malformed
#   input / no `pt` remote here) — consistent with model-pin-gate.sh's posture
#   — NEVER by silently guessing a personal-repo merge is the pt repo.

set -uo pipefail

# --- URL / command parsing helpers -------------------------------------------

# Extract "owner/repo" (as written; case untouched) from a GitHub HTTPS or SSH
# URL. The SSH arm intentionally matches ANY host token before the `:` (not
# just literal `github.com`) — see the 2026-06-02 HARNESS-GAP in docs/backlog.md
# ("broadcast-active-session.sh cannot parse SSH host-alias origin URLs"): a
# github.com-only case arm silently fails on an SSH `Host` alias like
# `github-pt`, which is exactly the `pt` remote's shape here. Empty if no match.
_owner_repo_from_url() {
  local url="$1"
  case "$url" in
    https://*/*/*)
      url="${url#https://}"
      url="${url#*/}"
      url="${url%.git}"
      printf '%s' "$url"
      ;;
    git@*:*/*)
      url="${url#git@*:}"
      url="${url%.git}"
      printf '%s' "$url"
      ;;
    *)
      ;;
  esac
}

_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Is this command shaped like a PR-merge? (`gh pr merge ...` or
# `gh api ... repos/OWNER/REPO/pulls/N/merge`). Grep-on-the-raw-command is the
# house style (same shape as the force-push/public-repo gates in
# settings.json.template) — a hook inspects the literal Bash command about to
# run, not an arbitrary free-text string, so light over-matching is acceptable.
_is_merge_command() {
  local cmd="$1"
  case "$cmd" in
    *gh\ pr\ merge*) return 0 ;;
  esac
  printf '%s' "$cmd" | grep -qE 'repos/[^/[:space:]]+/[^/[:space:]]+/pulls/[0-9]+/merge' && return 0
  return 1
}

# Explicit repo in a `gh api .../repos/OWNER/REPO/pulls/N/merge` path. Empty if
# no match.
_extract_api_merge_owner_repo() {
  local cmd="$1" m
  m="$(printf '%s' "$cmd" | grep -oE 'repos/[^/[:space:]"'"'"']+/[^/[:space:]"'"'"']+/pulls/[0-9]+/merge' | head -1)"
  [ -z "$m" ] && return 1
  printf '%s' "$m" | sed -E 's#repos/([^/]+)/([^/]+)/pulls/.*#\1/\2#'
  return 0
}

# Explicit `--repo`/`-R` flag value off a `gh pr merge` command (raw value —
# may be "owner/repo" or a full URL; caller normalizes). Empty if none.
_extract_repo_flag() {
  local cmd="$1" val=""
  val="$(printf '%s' "$cmd" | grep -oE -- '--repo=[^ ]+' | head -1)"
  if [ -n "$val" ]; then
    val="${val#--repo=}"
  else
    val="$(printf '%s' "$cmd" | grep -oE -- '--repo +[^ ]+' | head -1)"
    if [ -n "$val" ]; then
      val="$(printf '%s' "$val" | sed -E 's/^--repo +//')"
    else
      val="$(printf '%s' "$cmd" | grep -oE -- '(^| )-R +[^ ]+' | head -1)"
      [ -n "$val" ] && val="$(printf '%s' "$val" | sed -E 's/^ ?-R +//')"
    fi
  fi
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  printf '%s' "$val"
}

# `gh repo set-default`'s own persistence mechanism: `remote.<name>.gh-resolved
# = base`. Echoes the remote NAME if one is marked default; empty otherwise.
_default_remote_via_gh_resolved() {
  local dir="$1" out key val remote
  out="$(git -C "$dir" config --get-regexp '^remote\..*\.gh-resolved$' 2>/dev/null)" || return 0
  [ -z "$out" ] && return 0
  while IFS=' ' read -r key val; do
    if [ "$val" = "base" ]; then
      remote="${key#remote.}"
      remote="${remote%.gh-resolved}"
      printf '%s' "$remote"
      return 0
    fi
  done <<< "$out"
}

# Remote heuristic: the sole github.com-hosted (or $GH_HOST-hosted) remote is
# the resolvable default, matching gh's own candidate filtering (an SSH
# host-alias remote is invisible to this, same as it is to `gh` itself).
# Echoes "owner/repo" (lowercased) and returns 0 iff exactly one candidate;
# returns 1 (ambiguous: zero or more-than-one) otherwise.
_resolve_via_heuristic() {
  local dir="$1" gh_host="${GH_HOST:-github.com}"
  local name url owner_repo seen="" result="" count=0
  while IFS=$'\t' read -r name url; do
    [ -z "$name" ] && continue
    case "$url" in
      https://"$gh_host"/*|git@"$gh_host":*) ;;
      *) continue ;;
    esac
    owner_repo="$(_lower "$(_owner_repo_from_url "$url")")"
    [ -z "$owner_repo" ] && continue
    case " $seen " in *" $owner_repo "*) continue ;; esac
    seen="$seen $owner_repo"
    result="$owner_repo"
    count=$((count + 1))
  done < <(git -C "$dir" remote -v 2>/dev/null | awk '$3=="(fetch)"{print $1"\t"$2}')
  if [ "$count" -eq 1 ]; then
    printf '%s' "$result"
    return 0
  fi
  return 1
}

# Resolve the merge TARGET repo (lowercased "owner/repo") per the precedence in
# the file header. Echoes the target and returns 0 on success; returns 1 iff
# genuinely ambiguous/unresolvable.
_resolve_target_repo() {
  local cmd="$1" dir="$2" owner_repo val default_remote default_url heuristic

  owner_repo="$(_extract_api_merge_owner_repo "$cmd")"
  if [ -n "$owner_repo" ]; then
    _lower "$owner_repo"
    return 0
  fi

  val="$(_extract_repo_flag "$cmd")"
  if [ -n "$val" ]; then
    case "$val" in
      https://*|git@*) val="$(_owner_repo_from_url "$val")" ;;
    esac
    [ -n "$val" ] && { _lower "$val"; return 0; }
  fi

  default_remote="$(_default_remote_via_gh_resolved "$dir")"
  if [ -n "$default_remote" ]; then
    default_url="$(git -C "$dir" remote get-url "$default_remote" 2>/dev/null || echo "")"
    if [ -n "$default_url" ]; then
      owner_repo="$(_owner_repo_from_url "$default_url")"
      if [ -n "$owner_repo" ]; then
        _lower "$owner_repo"
        return 0
      fi
    fi
  fi

  if heuristic="$(_resolve_via_heuristic "$dir")"; then
    printf '%s' "$heuristic"
    return 0
  fi

  return 1
}

# --- gate ---------------------------------------------------------------

run_gate() {
  local input="${CLAUDE_TOOL_INPUT:-}"
  [ -z "$input" ] && input="$(cat 2>/dev/null || true)"
  [ -z "$input" ] && return 0                       # nothing to inspect -> fail-open
  command -v jq >/dev/null 2>&1 || return 0         # no jq -> fail-open (internal)

  local tool cmd
  tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  [ "$tool" = "Bash" ] || return 0                  # only the Bash surface

  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
  [ -n "$cmd" ] || return 0

  _is_merge_command "$cmd" || return 0              # not a merge-shaped command -> allow

  local dir="${GH_MERGE_GATE_REPO_DIR:-.}"
  local pt_url pt_repo
  pt_url="$(git -C "$dir" remote get-url pt 2>/dev/null || echo "")"
  [ -n "$pt_url" ] || return 0                       # no `pt` remote here -> gate N/A, fail-open

  pt_repo="$(_owner_repo_from_url "$pt_url")"
  pt_repo="$(_lower "$pt_repo")"
  [ -n "$pt_repo" ] || return 0                      # pt URL unparseable -> internal limitation

  local target
  if ! target="$(_resolve_target_repo "$cmd" "$dir")"; then
    {
      echo "================================================================"
      echo "GH-MERGE CANONICAL GATE — MERGE TARGET AMBIGUOUS/UNRESOLVABLE"
      echo "================================================================"
      echo "This command merges a PR but this hook could not determine, without a"
      echo "network call, which GitHub repo it targets (multiple candidate remotes,"
      echo "or none) — so it is refusing to guess in EITHER direction rather than"
      echo "silently allowing a possible pt-side merge or silently blocking a"
      echo "possible personal-side one."
      echo ""
      echo "  command: ${cmd}"
      echo ""
      echo "Fix ONE of:"
      echo "  1. Add an explicit --repo owner/name to the command."
      echo "  2. Run 'gh repo set-default' in this checkout to pin the default repo."
      echo ""
      echo "Decision: docs/decisions/064-never-diverge-single-canonical-master.md"
    } >&2
    return 2
  fi

  if [ "$target" = "$pt_repo" ]; then
    {
      echo "================================================================"
      echo "GH-MERGE CANONICAL GATE — PT-REPO MERGE BLOCKED"
      echo "================================================================"
      echo "This merge targets the work-org (pt) repo ('${target}'), which is the"
      echo "MIRROR, not canonical (decision 064). Per the 2026-05-29 posture"
      echo "reversal: personal 'origin' is now canonical; pt-side merges are what"
      echo "caused the 2026-07-15 14/10 master divergence."
      echo ""
      echo "Canonical flow: retarget this PR to the personal repo, or push the"
      echo "branch and open/merge the PR there instead. Any PT-side PR already"
      echo "in flight at cutover must be merged CANONICAL-side (this is a one-time"
      echo "migration note, not a recurring step)."
      echo ""
      echo "This gate is DEFENSE-IN-DEPTH, not the guarantee (amendments A1/A4):"
      echo "server-side GitHub branch protection on pt/master is the PRIMARY"
      echo "mechanism (covers web-UI/CI/collaborators too) and is an"
      echo "operator-only access-control change — surfaced separately, not"
      echo "agent-executable. Until it is enabled, this gate only covers the"
      echo "gh-CLI path on machines that have already synced it."
      echo ""
      echo "Decision: docs/decisions/064-never-diverge-single-canonical-master.md"
    } >&2
    return 2
  fi

  return 0
}

# --- self-test -----------------------------------------------------------

run_self_test() {
  local pass=0 fail=0
  local tmp; tmp="$(mktemp -d 2>/dev/null)" || { echo "mktemp FAIL"; exit 1; }

  _mk_repo() {
    local d="$tmp/$1"
    mkdir -p "$d"
    git -C "$d" init --quiet 2>/dev/null
    printf '%s' "$d"
  }

  _rc() { # <expected-rc> <name> <repo-dir> <json>
    local exp="$1" name="$2" dir="$3" json="$4" got
    CLAUDE_TOOL_INPUT="$json" GH_MERGE_GATE_REPO_DIR="$dir" bash "$SELF" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$exp" ]; then echo "  ok   $name (rc=$got)"; pass=$((pass + 1))
    else echo "  FAIL $name (rc=$got, expected $exp)"; fail=$((fail + 1)); fi
  }

  # Fixture A: pt configured; origin (github.com) is a DIFFERENT (personal) repo.
  local repoA; repoA="$(_mk_repo repoA)"
  git -C "$repoA" remote add pt "git@github-pt:acme-work/proj.git"
  git -C "$repoA" remote add origin "git@github.com:myuser/proj.git"

  _rc 2 "explicit --repo <pt-repo> -> BLOCK" "$repoA" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --repo acme-work/proj"}}'
  _rc 0 "explicit --repo <personal-repo> -> ALLOW" "$repoA" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --repo myuser/proj"}}'
  _rc 2 "gh api explicit path, pt-repo -> BLOCK" "$repoA" \
    '{"tool_name":"Bash","tool_input":{"command":"gh api -X PUT repos/acme-work/proj/pulls/42/merge"}}'
  _rc 0 "gh api explicit path, personal-repo -> ALLOW" "$repoA" \
    '{"tool_name":"Bash","tool_input":{"command":"gh api -X PUT repos/myuser/proj/pulls/42/merge"}}'
  _rc 2 "--repo case-insensitive match to pt -> BLOCK" "$repoA" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --repo ACME-WORK/PROJ"}}'
  _rc 0 "non-merge gh command (pr view) -> ALLOW" "$repoA" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr view 42 --repo acme-work/proj"}}'
  _rc 0 "non-merge gh command (pr create) -> ALLOW" "$repoA" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title x --body y --repo acme-work/proj"}}'
  _rc 0 "non-Bash tool -> allow" "$repoA" \
    '{"tool_name":"Edit","tool_input":{"command":"gh pr merge 1 --repo acme-work/proj"}}'
  _rc 0 "malformed json -> fail-open allow" "$repoA" 'this is not json'
  _rc 0 "empty input -> fail-open allow" "$repoA" ''

  # Fixture B: single github.com-shaped remote (origin) == pt's owner/repo ->
  # a BARE merge resolves via default-repo heuristic to pt -> BLOCK.
  local repoB; repoB="$(_mk_repo repoB)"
  git -C "$repoB" remote add pt "git@github-pt:acme-work/proj.git"
  git -C "$repoB" remote add origin "git@github.com:acme-work/proj.git"
  _rc 2 "bare merge, sole github-remote == pt -> BLOCK" "$repoB" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 7"}}'

  # Fixture C: single github.com-shaped remote (origin) == personal -> ALLOW.
  local repoC; repoC="$(_mk_repo repoC)"
  git -C "$repoC" remote add pt "git@github-pt:acme-work/proj.git"
  git -C "$repoC" remote add origin "git@github.com:myuser/proj.git"
  _rc 0 "bare merge, sole github-remote == personal -> ALLOW (the FP the design fears)" "$repoC" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 7"}}'

  # Fixture D: TWO github.com-shaped remotes, no gh-resolved default -> AMBIGUOUS.
  local repoD; repoD="$(_mk_repo repoD)"
  git -C "$repoD" remote add pt "git@github-pt:acme-work/proj.git"
  git -C "$repoD" remote add origin "git@github.com:myuser/proj.git"
  git -C "$repoD" remote add upstream "git@github.com:other-org/proj.git"
  _rc 2 "bare merge, 2 github-remotes, no default -> AMBIGUOUS block" "$repoD" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 7"}}'
  local out
  out="$(CLAUDE_TOOL_INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr merge 7"}}' GH_MERGE_GATE_REPO_DIR="$repoD" bash "$SELF" 2>&1 >/dev/null)"
  if printf '%s' "$out" | grep -qi "AMBIGUOUS"; then
    echo "  ok   ambiguous block names ambiguity (not the pt-block message)"; pass=$((pass + 1))
  else
    echo "  FAIL ambiguous block message missing 'AMBIGUOUS'"; fail=$((fail + 1))
  fi

  # Fixture E: 2 github-remotes, gh-resolved default explicitly set to the
  # pt-matching one -> BLOCK (proves gh-resolved wins over ambiguity).
  local repoE; repoE="$(_mk_repo repoE)"
  git -C "$repoE" remote add pt "git@github-pt:acme-work/proj.git"
  git -C "$repoE" remote add origin "git@github.com:acme-work/proj.git"
  git -C "$repoE" remote add fork "git@github.com:someoneelse/proj.git"
  git -C "$repoE" config remote.origin.gh-resolved base
  _rc 2 "bare merge, gh-resolved default == pt (among 2) -> BLOCK" "$repoE" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 7"}}'

  # Fixture F: 2 github-remotes, gh-resolved default explicitly set to the
  # personal one -> ALLOW (never silently blocks a personal-side merge even
  # when a same-owner pt-shaped remote also exists in the checkout).
  local repoF; repoF="$(_mk_repo repoF)"
  git -C "$repoF" remote add pt "git@github-pt:acme-work/proj.git"
  git -C "$repoF" remote add origin "git@github.com:myuser/proj.git"
  git -C "$repoF" remote add fork "git@github.com:acme-work/proj.git"
  git -C "$repoF" config remote.origin.gh-resolved base
  _rc 0 "bare merge, gh-resolved default == personal (among 2) -> ALLOW" "$repoF" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 7"}}'

  # Fixture G: no `pt` remote in this checkout at all -> gate not applicable ->
  # ALLOW even for an explicit --repo naming some third repo (an unrelated
  # project elsewhere on the estate must never be blocked).
  local repoG; repoG="$(_mk_repo repoG)"
  git -C "$repoG" remote add origin "git@github.com:someoneelse/unrelated.git"
  _rc 0 "no pt remote configured -> fail-open ALLOW (gate not applicable)" "$repoG" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 3 --repo someoneelse/unrelated"}}'

  rm -rf "$tmp" 2>/dev/null
  echo ""
  echo "gh-merge-canonical-gate self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

SELF="$0"
if [ "${1:-}" = "--self-test" ]; then run_self_test; exit $?; fi
run_gate
exit $?
