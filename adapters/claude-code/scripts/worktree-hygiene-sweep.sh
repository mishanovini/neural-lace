#!/usr/bin/env bash
# worktree-hygiene-sweep.sh — classify, report, and (with explicit approval) prune
# accumulated git worktrees. Originating incident: a downstream consumer repo
# accumulated 63 worktrees because parallel sessions never tore theirs down.
# This mechanism makes that accumulation visible-and-cleanable instead of silent.
#
# Usage:
#   worktree-hygiene-sweep.sh [repo ...]                 # REPORT ONLY (default)
#   worktree-hygiene-sweep.sh --prune [repo ...]         # prune SAFE-PRUNE entries
#                                                        #   (requires WORKTREE_SWEEP_APPROVE=1)
#   worktree-hygiene-sweep.sh --session-summary [repo ...]  # one line per repo when
#                                                        #   worktree count > 5
#   worktree-hygiene-sweep.sh --stranded [repo ...]         # human report of
#                                                        #   ORPHANED-HOLDS-CONTENT
#                                                        #   worktrees only (SILENT
#                                                        #   when none — see below)
#   worktree-hygiene-sweep.sh --stranded --porcelain [repo ...]  # TAB rows for
#                                                        #   machine consumers
#                                                        #   (harness-doctor.sh)
#   worktree-hygiene-sweep.sh --self-test                # scripted-scenario suite
#
# Repo selection: positional args are repo paths. With no args, all
# worktree-bearing repos under $HOME/claude-projects (depth <= 3) are discovered
# via `git worktree list` in each (repos with > 1 registered worktree).
#
# Classification (per registered worktree, primary ALWAYS skipped):
#   SAFE-PRUNE    = 0 unique patches (git cherry <base> <branch> has no '+' lines,
#                   base = origin/master | origin/main | master | main)
#                   AND 0 dirty files AND last commit older than N days
#                   (N default 7; env WORKTREE_SWEEP_AGE_DAYS).
#   HOLDS-CONTENT = anything else. NEVER touched by --prune. Structural-skip
#                   cases (detached-HEAD, locked, missing-directory/prunable,
#                   no-resolvable-base) stay plain HOLDS-CONTENT (never
#                   reasoned about further — fail toward silence).
#   For every OTHER HOLDS-CONTENT worktree (dir present, base resolved), this
#   is further split by a liveness join (session-heartbeat-lib.sh + the
#   concurrent-ownership-gate.sh claims-dir convention + a subagent-
#   transcript-mtime signal for agent-<id> worktrees — see REFORMULATION
#   note below) into:
#     LIVE-OWNED-HOLDS-CONTENT = for an `agent-<id>` worktree (a dispatched
#                   plan-phase-builder subagent, isolation:worktree) a fresh
#                   mtime on THAT AGENT'S OWN transcript file — the PRIMARY
#                   signal for these, since a dispatched subagent writes NO
#                   heartbeat of its own (see REFORMULATION note); OR, for
#                   any worktree, a live/throttled heartbeat, a CONTINUING-
#                   marker heartbeat still inside its grace window, a fresh
#                   same-repo session claim, or the invoking session's OWN
#                   worktree (SELF) covers it.
#     ORPHANED-HOLDS-CONTENT   = none of the above — dirty and/or unintegrated
#                   work with NO live owner. This is the `--stranded` set (see
#                   below). Already-integrated branches (git cherry patch-
#                   equivalence, OR the branch tip is an ancestor of
#                   origin/master | origin/main | master | main even when the
#                   single `resolve_base` ref used for the cherry count itself
#                   lags) are excluded from "unintegrated" for this split —
#                   the report table's raw UNIQUE column and the SAFE-PRUNE
#                   math above are computed exactly as before, unaffected.
#
# `--stranded` reuses this same per-repo worktree walk (primary always
# skipped) but reports ONLY the ORPHANED-HOLDS-CONTENT rows: SILENT (no
# output, exit 0) when none exist; otherwise a `[stranded-work] ...` block
# naming path/branch/dirty/unintegrated/age/liveness per row, plus a salvage
# reminder (the sweep still refuses to prune HOLDS-CONTENT of any kind).
# `--stranded --porcelain` prints the same rows TAB-delimited with no header,
# for harness-doctor.sh's check_orphaned_worktree_work to consume.
#
# REFORMULATION (docs/harness-improvements/orphaned-worktree-guard.md —
# harness-review REFORMULATE verdict on the original WIP, a4b6876): the
# liveness join's ORIGINAL design relied ONLY on session heartbeats, but a
# dispatched plan-phase-builder subagent (isolation:worktree) writes NO
# heartbeat of its own — only a top-level session's heartbeat writer runs
# (harness-doctor.sh's own obs-heartbeats-fresh predicate proved this). That
# meant an ACTIVELY-RUNNING builder's dirty `agent-<id>` worktree would be
# classified stranded on every parallel-build day (a cry-wolf false
# positive). Fix: for a worktree whose basename matches `agent-*` (the
# harness's own dispatch-time naming convention — confirmed empirically,
# not from memory, against this session's own worktree + its transcript at
# `<session-dir>/subagents/agent-<id>.jsonl`, NOT `tasks/<id>.output` as an
# earlier draft of this note guessed), `_live_owner` treats that agent's
# OWN transcript mtime as the PRIMARY liveness signal — see
# `_agent_tx_fresh_min` / `AGENT_TX_FRESH_MIN` below — because the harness
# names an agent's transcript file identically to its worktree's own
# basename at dispatch time, so no id-parsing or dispatch-path change is
# needed. The heartbeat/claim join remains the ONLY signal for non-agent
# (named, e.g. `sweet-hamilton-c9a5b6`) worktrees, unchanged.
#
# APPROVAL CHANNEL (Misha's standing order, 2026-06-09): nothing is deleted
# without his explicit approval. The env flag WORKTREE_SWEEP_APPROVE=1 IS that
# approval channel — --prune without it refuses (exit 3) and removes nothing.
# Removal uses `git worktree remove` (no --force) + `git branch -d` (NOT -D;
# -d refuses unmerged branches as a second, git-native guard). Every removal is
# logged to $WORKTREE_SWEEP_LOG (default ~/.claude/state/worktree-sweep.log).
#
# Stash census: per repo, `git stash list` count + ages are REPORTED ONLY.
# This script never drops stashes.
#
# Portability: Bash 3.2 (no associative arrays, no mapfile, no ${var,,}).
# Windows-safe: paths are parsed from `git worktree list --porcelain` by line
# prefix only — NEVER split on ':' (drive-colon paths like C:/Users/... are a
# known footgun).
#
# Exit codes: 0 ok; 2 usage error; 3 --prune without WORKTREE_SWEEP_APPROVE=1;
#             1 self-test failure.

set -u

AGE_DAYS="${WORKTREE_SWEEP_AGE_DAYS:-7}"
SWEEP_LOG="${WORKTREE_SWEEP_LOG:-$HOME/.claude/state/worktree-sweep.log}"
NOW_TS="$(date +%s)"

# ---- liveness join (stranded-work extension) --------------------------
# Shared read-side heartbeat classifier (hb_state_dir / hb_classify /
# _hb_field / _hb_epoch) — the SAME lib session-heartbeat.sh's own `sweep`
# verb and harness-doctor.sh's obs-heartbeats-fresh check use, so "is this
# worktree's owner alive" is never a second, drifting implementation of
# that question. Best-effort: an unresolvable lib degrades every worktree to
# "no heartbeat/claim" (fail toward reporting, never toward a crash) rather
# than aborting the sweep.
# shellcheck disable=SC1091
source "$(dirname "$0")/../hooks/lib/session-heartbeat-lib.sh" 2>/dev/null || true

# Fresh-claim join config — mirrors concurrent-ownership-gate.sh's own
# COG_CLAIMS_DIR/COG_CLAIM_FRESH_SECONDS resolution exactly (same claims
# dir, same freshness window, same HARNESS_SELFTEST sandboxing contract) so
# a claim written by that gate's future claim/unclaim lifecycle (currently
# a no-op — CLAIM-LIFECYCLE-01) is honored identically here.
if [ "${HARNESS_SELFTEST:-0}" = "1" ]; then
  COG_CLAIMS_DIR="${COG_CLAIMS_DIR:-${TMPDIR:-/tmp}/whs-selftest-claims-$$}"
else
  COG_CLAIMS_DIR="${COG_CLAIMS_DIR:-$HOME/.claude/state/active-session-broadcast/claims}"
fi
COG_CLAIM_FRESH_SECONDS="${COG_CLAIM_FRESH_SECONDS:-7200}"

# Mode-(b) hardening: a CONTINUING marker_state is treated as owned for this
# many minutes past its heartbeat's last_activity_ts (mirrors session-
# resumer.sh's "in-flight signal -> not abandoned"; wider than OBS_STALE_MIN
# because a scheduled wake can legitimately be tens of minutes out).
CONTINUING_GRACE="${CONTINUING_GRACE:-90}"

# Subagent-transcript liveness window (REFORMULATION fix — see file header).
# A dispatched plan-phase-builder subagent (isolation:worktree) writes NO
# heartbeat of its own, so an `agent-<id>` worktree's PRIMARY liveness
# signal is that agent's own transcript file's mtime (updated on every
# turn/tool call while it works). Same default as OBS_STALE_MIN (the
# session-level heartbeat-staleness window this file's heartbeat join
# already uses) for one consistent "how long is silence still normal"
# answer across both liveness paths; independently overridable. Residual:
# an agent that goes quiet for longer than this window while genuinely
# still working (a single very long reasoning/tool call with no
# intermediate transcript flush) could false-fire past the window — this
# is accepted for a WARN-only, never-auto-pruning surfacer (see
# manifest.json's stranded-worktree-work fp_expectation/honesty_rationale
# for the full acceptance argument).
AGENT_TX_FRESH_MIN="${AGENT_TX_FRESH_MIN:-${OBS_STALE_MIN:-30}}"

# Resolved once: the invoking session's OWN worktree (SELF exclusion,
# requirement 5.i/5.iii) — belt-and-suspenders for the instant before this
# session's own heartbeat exists. Empty when not inside a git worktree at
# all (e.g. a bare discover_repos sweep run from outside any repo).
SELF_TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# ---------------------------------------------------------------- helpers ---

# Normalize a path for equality comparison across Git Bash (/c/Users/...),
# Windows drive-letter (C:/Users/...), and backslash forms. Lowercased.
# Same technique as concurrent-ownership-gate.sh's _norm_path (that file's
# line ~137) — deliberately NOT REQUIRED to resolve via `cd -P` here (unlike
# that gate's version): a stranded worktree's directory may itself be
# exactly the thing under question (or already removed), so this helper
# must be able to compare path STRINGS without requiring the path to
# currently exist.
#
# OPPORTUNISTIC CANONICALIZATION (Windows/MSYS mount-alias fix): when $1
# IS currently a real, existing directory, prefer the OS's own canonical
# form first — via `pwd -W` (Git-Bash/MSYS builtin) else `cygpath -m` when
# available — before the string rewrite below. This closes a real gap the
# string rewrite alone cannot: MSYS mount aliases (e.g. `/tmp/...`, which
# this shell's own `mktemp -d` returns) name the SAME physical directory as
# their Windows drive-letter form (e.g.
# `C:/Users/<u>/AppData/Local/Temp/...`, which is what `git worktree list
# --porcelain` reports for a worktree registered under that same /tmp
# path) — two textually-unrelated strings for one directory, which no
# drive-letter regex can rewrite because neither side "looks like" the
# other's pattern. Resolving through the filesystem is safe and never
# widens the contract: it only ever activates for paths that demonstrably
# exist right now, so an already-removed or not-yet-created path (the
# exact case the "no cd -P" rule protects) still falls through to pure
# string normalization, unchanged. On non-Windows platforms neither
# `pwd -W` nor `cygpath` exists, so $resolved stays empty and behavior is
# identical to before this fix.
_norm_path() {
  local p="$1"
  if [ -d "$p" ]; then
    local resolved
    resolved="$(cd "$p" 2>/dev/null && pwd -W 2>/dev/null)"
    if [ -z "$resolved" ] && command -v cygpath >/dev/null 2>&1; then
      resolved="$(cygpath -m "$p" 2>/dev/null)"
    fi
    [ -n "$resolved" ] && p="$resolved"
  fi
  p="${p//\\//}"
  if [[ "$p" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    local d rest
    d=$(printf '%s' "${BASH_REMATCH[1]}" | tr 'A-Z' 'a-z')
    rest="${BASH_REMATCH[2]}"
    p="/${d}${rest}"
  fi
  while [[ "$p" == *"//"* ]]; do p="${p//\/\///}"; done
  printf '%s' "$p" | tr 'A-Z' 'a-z'
}

# Repo identity for claim scoping — MUST mirror broadcast-active-session.sh
# / concurrent-ownership-gate.sh's _repo_identity exactly: origin push URL
# when one exists, else the absolute git common dir (shared by every linked
# worktree of one repo). Claims are machine-global; this is what keeps a
# claim on repo A from ever covering repo B's same-named branch.
_whs_repo_identity() {
  local url
  url="$(git -C "$1" remote get-url --push origin 2>/dev/null || true)"
  if [ -n "$url" ]; then
    printf '%s' "$url"
    return 0
  fi
  git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true
}

# ---- subagent-transcript-mtime liveness (REFORMULATION fix) -----------
# The REAL layout (verified empirically against this session's own
# transcript — NOT trusted from memory/an earlier draft note, which
# guessed `tasks/<id>.output` and was wrong): a dispatched agent's
# transcript lives at
#   <projects-root>/<project-slug>/<session-id>/subagents/agent-<id>.jsonl
# with a sidecar `agent-<id>.meta.json` (carries worktreePath/
# worktreeBranch/agentType — not needed for the join below, since the
# harness already names the worktree directory ITSELF `agent-<id>`,
# identical to the transcript's own filename stem; matching by exact
# basename is therefore both simpler and more robust than re-deriving an
# id and cross-checking a sidecar field). The transcript is appended to
# continuously while the agent works (same "still writing" logic
# session-heartbeat-lib.sh's own transcript-mtime join already relies on
# for top-level sessions) — so its mtime is direct, platform-independent
# liveness evidence requiring no cooperating heartbeat write from the
# subagent at all.

# _agent_tx_root — resolution mirrors session-heartbeat-lib.sh's
# _hb_transcripts_dir EXACTLY (OBS_TRANSCRIPTS_ROOT override for
# self-test sandboxing, else the real per-user transcripts root) so both
# transcript readers in this harness honor the identical sandboxing
# variable. Never fails; always prints a non-empty path.
_agent_tx_root() {
  if [ -n "${OBS_TRANSCRIPTS_ROOT:-}" ]; then
    printf '%s' "$OBS_TRANSCRIPTS_ROOT"
    return 0
  fi
  printf '%s/.claude/projects' "${HOME:-$PWD}"
}

# _build_agent_tx_cache — walks _agent_tx_root ONCE per sweep-script
# PROCESS and caches every `agent-*.jsonl` path found (maxdepth 6 covers
# the real 4-deep layout above with slack for a deeper nesting variant,
# while still being a single bounded `find`, never an unbounded
# recursive walk). Idempotent: a second call in the same process is a
# no-op. This is the bounded-scan discipline this codebase's own history
# requires (an unbounded fork-a-`find`-PER-WORKTREE-PER-SWEEP scan has
# shipped as a real defect at least twice before) — every worktree
# needing a liveness check in this run looks up THIS cache
# (`_agent_tx_fresh_min`, below) instead of re-walking the tree.
_AGENT_TX_CACHE_FILE=""
_AGENT_TX_CACHE_BUILT=0
_build_agent_tx_cache() {
  [ "$_AGENT_TX_CACHE_BUILT" = "1" ] && return 0
  _AGENT_TX_CACHE_FILE="$(mktemp)"
  find "$(_agent_tx_root)" -maxdepth 6 -type f -name 'agent-*.jsonl' 2>/dev/null > "$_AGENT_TX_CACHE_FILE"
  _AGENT_TX_CACHE_BUILT=1
  return 0
}

# _agent_tx_fresh_min <agent_id> — prints the matching subagent
# transcript's mtime age in MINUTES (looked up against the cache built
# by _build_agent_tx_cache — never a fresh `find` call), or empty when no
# transcript named exactly "<agent_id>.jsonl" exists in the cache.
# <agent_id> is the worktree's OWN basename ("agent-<hex>"), which the
# harness names identically to that agent's transcript file stem at
# dispatch time (see block comment above). Anchored match (directory
# separator or start-of-line, then the literal id, then ".jsonl",
# end-of-line) so "agent-1" can never match a cached "agent-12.jsonl".
# Never errors.
_agent_tx_fresh_min() {
  local agent_id="$1" tf mtime now_epoch
  _build_agent_tx_cache
  [ -s "$_AGENT_TX_CACHE_FILE" ] || { printf ''; return 0; }
  tf="$(grep -E "(^|/)${agent_id}\.jsonl\$" "$_AGENT_TX_CACHE_FILE" 2>/dev/null | head -1)"
  [ -n "$tf" ] && [ -f "$tf" ] || { printf ''; return 0; }
  mtime="$(date -u -r "$tf" +%s 2>/dev/null || stat -c %Y "$tf" 2>/dev/null || stat -f %m "$tf" 2>/dev/null || echo 0)"
  [ "$mtime" -gt 0 ] 2>/dev/null || { printf ''; return 0; }
  now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
  printf '%d' $(( (now_epoch - mtime) / 60 ))
}

# _effective_unintegrated <repo> <branch> <raw_unique> — requirement 5.ii's
# ALREADY-MERGED exclusion. <raw_unique> is the EXISTING R_UNIQUE (git
# cherry <base> <branch> '+' count against the single ref resolve_base
# picked) — untouched by this function, still the report table's ground
# truth and the SAFE-PRUNE math's input. This function answers a narrower
# question for the stranded-work split only: does origin/master (or
# whichever ref resolve_base picked) merely LAG a merge/cherry-pick that
# already landed on local master? Checked by testing ancestry against ALL
# FOUR candidate integration refs (not just the one resolve_base chose),
# which closes exactly that origin-vs-local gap: git cherry alone would
# still show '+' against a stale origin/master even though the branch is
# fully merged into local master. Never mutates raw_unique; only used to
# decide HAS_CONTENT for the ORPHANED split.
_effective_unintegrated() {
  local repo="$1" branch="$2" raw="$3" alt
  if [ "$raw" = "0" ] || [ -z "$raw" ]; then
    printf '0'
    return 0
  fi
  for alt in origin/master origin/main master main; do
    if git -C "$repo" rev-parse --verify --quiet "$alt" >/dev/null 2>&1; then
      if git -C "$repo" merge-base --is-ancestor "refs/heads/$branch" "$alt" 2>/dev/null; then
        printf '0'
        return 0
      fi
    fi
  done
  printf '%s' "$raw"
}

# _live_owner <wt_path> <repo> — true (rc 0) iff worktree $1 of repo $2 is
# owned by a live process per the signals below. Sets LIVE_OWNER_VERDICT to
# the label used in reports:
#   true  (owned):     agent-transcript-fresh | live | throttled |
#                       continuing-grace | claim
#   false (orphaned):  agent-transcript-stale | crashed | stale |
#                       "no heartbeat/claim"
# Priority order (requirement's LIVE_OWNED definition):
#   0. REFORMULATION fix (agent-<id> worktrees ONLY — see file header):
#      when basename($wt_path) matches `agent-*` (the harness's own
#      dispatch-time naming for an isolation:worktree subagent), that
#      agent's OWN transcript mtime is the PRIMARY signal, checked FIRST
#      and returned immediately when fresh — a dispatched subagent writes
#      NO heartbeat of its own, so waiting on step 1 below for these would
#      always fall through to "no heartbeat/claim" regardless of whether
#      the builder is actively working. Found-but-stale is remembered
#      (agent_tx_age) and used as the final verdict at the bottom of this
#      function ONLY if nothing else below claims ownership either.
#   1. Heartbeat join: any heartbeat file whose worktree_root normalizes to
#      $wt_path. hb_classify live/throttled -> owned outright (this already
#      folds in the transcript-mtime override for a long tool-heavy turn —
#      see session-heartbeat-lib.sh's hb_is_stale — a DIFFERENT transcript
#      join than step 0: that one is a top-level session's OWN transcript,
#      keyed by session_id; step 0 above is a dispatched SUBAGENT's own
#      transcript, keyed by agent id, which no heartbeat file references at
#      all). Else, a CONTINUING marker_state within CONTINUING_GRACE
#      minutes of last_activity_ts is ALSO owned (mode-(b) hardening:
#      standing-by awaiting a scheduled wake). Otherwise the heartbeat's own
#      classification (crashed/stale) becomes the reported liveness.
#   2. Fresh-claim join (best-effort OR — can only ADD ownership, so an
#      empty/absent claims dir yields false-NEGATIVES, never false-
#      positives; see file header CLAIM-LIFECYCLE-01 note): a fresh
#      same-repo claim naming this worktree.
# Never errors; a missing lib/dir simply yields "no heartbeat/claim" (or,
# for a recognized-but-stale agent worktree, "agent-transcript-stale").
_live_owner() {
  local wt_path="$1" repo="$2" wt_norm hb_dir h found_hb=0 cls
  local agent_id="" agent_tx_age=""
  LIVE_OWNER_VERDICT=""
  wt_norm="$(_norm_path "$wt_path")"

  case "$(basename "$wt_path")" in
    agent-*) agent_id="$(basename "$wt_path")" ;;
  esac
  if [ -n "$agent_id" ]; then
    agent_tx_age="$(_agent_tx_fresh_min "$agent_id")"
    if [ -n "$agent_tx_age" ] && [ "$agent_tx_age" -le "$AGENT_TX_FRESH_MIN" ] 2>/dev/null; then
      LIVE_OWNER_VERDICT="agent-transcript-fresh"
      return 0
    fi
  fi

  if command -v hb_state_dir >/dev/null 2>&1; then
    hb_dir="$(hb_state_dir 2>/dev/null || true)"
    if [ -n "$hb_dir" ] && [ -d "$hb_dir" ]; then
      for h in "$hb_dir"/*.json; do
        [ -f "$h" ] || continue
        local wtr
        wtr="$(_hb_field "$h" worktree_root 2>/dev/null || true)"
        [ -n "$wtr" ] || continue
        [ "$(_norm_path "$wtr")" = "$wt_norm" ] || continue
        found_hb=1
        cls="$(hb_classify "$h" 2>/dev/null || echo missing)"
        if [ "$cls" = "live" ] || [ "$cls" = "throttled" ]; then
          LIVE_OWNER_VERDICT="$cls"
          return 0
        fi
        local marker
        marker="$(_hb_field "$h" marker_state 2>/dev/null || true)"
        if [ "$marker" = "CONTINUING" ]; then
          local last_ts last_epoch now_epoch age_min
          last_ts="$(_hb_field "$h" last_activity_ts 2>/dev/null || true)"
          if [ -n "$last_ts" ]; then
            last_epoch="$(_hb_epoch "$last_ts" 2>/dev/null || echo 0)"
            now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
            if [ "$last_epoch" -gt 0 ]; then
              age_min=$(( (now_epoch - last_epoch) / 60 ))
              if [ "$age_min" -le "$CONTINUING_GRACE" ]; then
                LIVE_OWNER_VERDICT="continuing-grace"
                return 0
              fi
            fi
          fi
        fi
        [ -n "$LIVE_OWNER_VERDICT" ] || LIVE_OWNER_VERDICT="$cls"
      done
    fi
  fi

  if [ -d "$COG_CLAIMS_DIR" ]; then
    local repo_id cutoff f wt rid
    repo_id="$(_whs_repo_identity "$repo")"
    cutoff="$(date -d "-${COG_CLAIM_FRESH_SECONDS} seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
    if [ -n "$cutoff" ]; then
      while IFS= read -r f; do
        [ -f "$f" ] || continue
        wt="$(sed -nE 's/.*"worktree"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -1)"
        rid="$(sed -nE 's/.*"repo"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -1)"
        [ -n "$wt" ] || continue
        [ -n "$rid" ] || continue
        [ "$(_norm_path "$rid")" = "$(_norm_path "$repo_id")" ] || continue
        [ "$(_norm_path "$wt")" = "$wt_norm" ] || continue
        LIVE_OWNER_VERDICT="claim"
        return 0
      done < <(find "$COG_CLAIMS_DIR" -maxdepth 1 -type f -name '*.json' -newermt "$cutoff" 2>/dev/null)
    fi
  fi

  if [ "$found_hb" = "1" ]; then
    [ -n "$LIVE_OWNER_VERDICT" ] || LIVE_OWNER_VERDICT="stale"
  elif [ -n "$agent_id" ] && [ -n "$agent_tx_age" ]; then
    # Recognized agent worktree with a transcript we found but which is
    # PAST AGENT_TX_FRESH_MIN — more informative than the generic
    # "no heartbeat/claim" (which would otherwise imply "we have no signal
    # at all" when we in fact have a stale one).
    LIVE_OWNER_VERDICT="agent-transcript-stale"
  else
    LIVE_OWNER_VERDICT="no heartbeat/claim"
  fi
  return 1
}

# Emit "path<TAB>branch<TAB>flags" per registered worktree (flags: detached,
# bare, locked, prunable, comma-joined; "-" if none; branch "-" if none).
# First emitted line is the primary worktree. Tab-delimited so drive-colon
# Windows paths are never split.
list_worktrees() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    function flush() {
      if (path != "") {
        if (flags == "") flags = "-"
        if (branch == "") branch = "-"
        printf "%s\t%s\t%s\n", path, branch, flags
      }
      path = ""; branch = ""; flags = ""
    }
    /^worktree /  { flush(); path = substr($0, 10) }
    /^branch /    { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
    /^detached$/  { flags = flags (flags == "" ? "" : ",") "detached" }
    /^bare$/      { flags = flags (flags == "" ? "" : ",") "bare" }
    /^locked/     { flags = flags (flags == "" ? "" : ",") "locked" }
    /^prunable/   { flags = flags (flags == "" ? "" : ",") "prunable" }
    END { flush() }
  '
}

# Resolve the comparison base for unique-patch detection. Echoes ref or nothing.
resolve_base() {
  local repo="$1" ref
  for ref in origin/master origin/main master main; do
    if git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      echo "$ref"
      return 0
    fi
  done
  return 1
}

# Classify one worktree. Sets globals: R_DIRTY R_UNIQUE R_AGE R_CLASS R_NOTE
# R_LIVENESS. R_CLASS is one of SAFE-PRUNE | HOLDS-CONTENT |
# LIVE-OWNED-HOLDS-CONTENT | ORPHANED-HOLDS-CONTENT (the latter two are the
# stranded-work liveness split of the HOLDS-CONTENT bucket; see file header).
classify_worktree() {
  local repo="$1" wt_path="$2" branch="$3" flags="$4" base="$5"
  R_DIRTY="?"; R_UNIQUE="?"; R_AGE="?"; R_CLASS="HOLDS-CONTENT"; R_NOTE=""; R_LIVENESS=""

  case ",$flags," in
    *,prunable,*)
      R_NOTE="stale-registration (dir missing)"; return 0 ;;
    *,locked,*)
      R_NOTE="locked"; return 0 ;;
    *,detached,*)
      R_NOTE="detached HEAD"; return 0 ;;
  esac

  if [ ! -d "$wt_path" ]; then
    R_NOTE="dir missing"; return 0
  fi

  # dirty count (tracked changes + untracked files)
  R_DIRTY="$(git -C "$wt_path" status --porcelain 2>/dev/null | grep -c . || true)"
  [ -n "$R_DIRTY" ] || R_DIRTY=0

  # last-commit age in days
  local ct
  ct="$(git -C "$repo" log -1 --format=%ct "refs/heads/$branch" 2>/dev/null || true)"
  if [ -n "$ct" ]; then
    R_AGE=$(( (NOW_TS - ct) / 86400 ))
  fi

  if [ -z "$base" ]; then
    R_NOTE="no base ref (origin/master|main missing)"; return 0
  fi

  # unique patches vs base
  R_UNIQUE="$(git -C "$repo" cherry "$base" "refs/heads/$branch" 2>/dev/null | grep -c '^+' || true)"
  [ -n "$R_UNIQUE" ] || R_UNIQUE=0

  if [ "$R_UNIQUE" = "0" ] && [ "$R_DIRTY" = "0" ] && [ "$R_AGE" != "?" ] && [ "$R_AGE" -gt "$AGE_DAYS" ]; then
    R_CLASS="SAFE-PRUNE"
  fi

  # ---- stranded-work liveness split (does NOT touch the SAFE-PRUNE math
  # above, which is already computed and final by this point) ----
  if [ "$R_CLASS" = "HOLDS-CONTENT" ]; then
    local eff_unique has_content=0
    eff_unique="$(_effective_unintegrated "$repo" "$branch" "$R_UNIQUE")"
    [ "$R_DIRTY" != "0" ] && has_content=1
    [ "$eff_unique" != "0" ] && has_content=1
    if [ "$has_content" = "1" ]; then
      if [ -n "${SELF_TOPLEVEL:-}" ] && [ "$(_norm_path "$wt_path")" = "$(_norm_path "$SELF_TOPLEVEL")" ]; then
        R_CLASS="LIVE-OWNED-HOLDS-CONTENT"
        R_LIVENESS="self"
      elif _live_owner "$wt_path" "$repo"; then
        R_CLASS="LIVE-OWNED-HOLDS-CONTENT"
        R_LIVENESS="$LIVE_OWNER_VERDICT"
      else
        R_CLASS="ORPHANED-HOLDS-CONTENT"
        R_LIVENESS="$LIVE_OWNER_VERDICT"
      fi
    fi
  fi
  return 0
}

# Print stash census for a repo (report-only — never drops stashes).
stash_census() {
  local repo="$1" count line ts age
  count="$(git -C "$repo" stash list 2>/dev/null | grep -c . || true)"
  [ -n "$count" ] || count=0
  echo "  Stashes: $count"
  if [ "$count" -gt 0 ]; then
    git -C "$repo" stash list --format='%gd%x09%ct%x09%gs' 2>/dev/null |
      while IFS="$(printf '\t')" read -r ref ts msg; do
        age=$(( (NOW_TS - ts) / 86400 ))
        echo "    $ref: ${age}d old — $msg"
      done
  fi
}

# Sweep one repo. $1=repo $2=mode(report|prune|summary)
# Writes classification rows to $ROWS_FILE as: class<TAB>path<TAB>branch
sweep_repo() {
  local repo="$1" mode="$2"
  local base wt_list primary_seen path branch flags
  local wt_count=0 safe_count=0

  base="$(resolve_base "$repo" || true)"

  wt_list="$(mktemp)"
  list_worktrees "$repo" > "$wt_list"
  : > "$ROWS_FILE"

  if [ "$mode" != "summary" ] && [ "$mode" != "stranded" ]; then
    echo ""
    echo "== repo: $repo (base: ${base:-NONE}, age threshold: ${AGE_DAYS}d) =="
    printf '  %-58s %-34s %5s %6s %6s  %s\n' "WORKTREE" "BRANCH" "DIRTY" "UNIQUE" "AGE_D" "CLASS"
  fi

  primary_seen=0
  while IFS="$(printf '\t')" read -r path branch flags; do
    [ -n "$path" ] || continue
    if [ "$primary_seen" = "0" ]; then
      primary_seen=1   # primary worktree: ALWAYS skipped, never classified/pruned
      continue
    fi
    wt_count=$(( wt_count + 1 ))
    classify_worktree "$repo" "$path" "$branch" "$flags" "$base"
    if [ "$R_CLASS" = "SAFE-PRUNE" ]; then
      safe_count=$(( safe_count + 1 ))
    fi
    printf '%s\t%s\t%s\n' "$R_CLASS" "$path" "$branch" >> "$ROWS_FILE"
    if [ "$mode" = "stranded" ]; then
      if [ "$R_CLASS" = "ORPHANED-HOLDS-CONTENT" ]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$path" "$branch" "$R_DIRTY" "$R_UNIQUE" "$R_AGE" "$R_LIVENESS" >> "$STRANDED_ROWS_FILE"
      fi
    elif [ "$mode" != "summary" ]; then
      local note_sfx=""
      [ -n "$R_NOTE" ] && note_sfx="  ($R_NOTE)"
      printf '  %-58s %-34s %5s %6s %6s  %s%s\n' "$path" "$branch" "$R_DIRTY" "$R_UNIQUE" "$R_AGE" "$R_CLASS" "$note_sfx"
    fi
  done < "$wt_list"
  rm -f "$wt_list"

  if [ "$mode" = "stranded" ]; then
    return 0
  fi

  if [ "$mode" = "summary" ]; then
    if [ "$wt_count" -gt 5 ]; then
      echo "repo $repo: $wt_count worktrees, $safe_count safe-prune candidates — run worktree-hygiene-sweep.sh"
    fi
    return 0
  fi

  if [ "$wt_count" = "0" ]; then
    echo "  (no secondary worktrees)"
  else
    echo "  Total: $wt_count worktree(s), $safe_count SAFE-PRUNE candidate(s)"
  fi
  stash_census "$repo"

  if [ "$mode" = "prune" ]; then
    prune_safe "$repo"
  fi
  return 0
}

# Prune SAFE-PRUNE rows from $ROWS_FILE. Approval already checked in main.
prune_safe() {
  local repo="$1" class path branch ts
  while IFS="$(printf '\t')" read -r class path branch; do
    [ "$class" = "SAFE-PRUNE" ] || continue
    if git -C "$repo" worktree remove "$path" 2>/dev/null; then
      if [ "$branch" != "-" ]; then
        if ! git -C "$repo" branch -d "$branch" >/dev/null 2>&1; then
          echo "  PRUNED worktree $path (branch $branch NOT deleted — branch -d refused; left in place)"
        else
          echo "  PRUNED worktree $path + branch $branch"
        fi
      else
        echo "  PRUNED worktree $path (no branch)"
      fi
      mkdir -p "$(dirname "$SWEEP_LOG")"
      ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "$ts repo=$repo removed worktree=$path branch=$branch" >> "$SWEEP_LOG"
    else
      echo "  SKIP $path — git worktree remove refused (state changed since classification?)"
    fi
  done < "$ROWS_FILE"
}

# _emit_stranded — reads $STRANDED_ROWS_FILE (path<TAB>branch<TAB>dirty<TAB>
# unique<TAB>age<TAB>liveness, one row per ORPHANED-HOLDS-CONTENT worktree
# accumulated across every repo swept in --stranded mode) and prints per the
# emit contract:
#   --porcelain: one machine row per line, tag-prefixed
#     (ORPHANED-HOLDS-CONTENT<TAB>path<TAB>branch<TAB>dirty<TAB>unintegrated
#     <TAB>age_days<TAB>liveness); empty output (no header) when none.
#   default (human): SILENT (nothing, exit 0) when the file is empty;
#     otherwise the "[stranded-work] ..." block + salvage reminder.
_emit_stranded() {
  if [ ! -s "$STRANDED_ROWS_FILE" ]; then
    return 0
  fi

  if [ "$PORCELAIN" = "1" ]; then
    while IFS="$(printf '\t')" read -r path branch dirty unique age liveness; do
      [ -n "$path" ] || continue
      printf 'ORPHANED-HOLDS-CONTENT\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$path" "$branch" "$dirty" "$unique" "$age" "$liveness"
    done < "$STRANDED_ROWS_FILE"
    return 0
  fi

  local count
  count="$(grep -c . "$STRANDED_ROWS_FILE" 2>/dev/null || true)"
  [ -n "$count" ] || count=0
  echo "[stranded-work] ${count} worktree(s) hold uncommitted or unintegrated work with NO live owner:"
  while IFS="$(printf '\t')" read -r path branch dirty unique age liveness; do
    [ -n "$path" ] || continue
    local hb_note
    case "$liveness" in
      "no heartbeat/claim"|"")
        hb_note="no heartbeat/claim" ;;
      agent-transcript-*)
        hb_note="liveness=${liveness}" ;;
      *)
        hb_note="heartbeat=${liveness}" ;;
    esac
    printf '  \xe2\x80\xa2 %s  branch %s  (dirty=%s, unintegrated=%s, last commit %sd ago; %s)\n' \
      "$path" "$branch" "$dirty" "$unique" "$age" "$hb_note"
  done < "$STRANDED_ROWS_FILE"
  echo "  Salvage BEFORE removing (the sweep refuses to prune HOLDS-CONTENT): cd <path> && git status;"
  echo "  commit + cherry-pick to master (or git stash), then \`git worktree remove <path>\`."
  return 0
}

# Discover worktree-bearing repos under ~/claude-projects (depth <= 3),
# deduplicated by primary-worktree path.
discover_repos() {
  local seen gitdir repo primary count
  seen="$(mktemp)"
  find "$HOME/claude-projects" -maxdepth 3 -name .git \( -type d -o -type f \) 2>/dev/null |
    while read -r gitdir; do
      repo="$(dirname "$gitdir")"
      primary="$(list_worktrees "$repo" | head -1 | cut -f1)"
      [ -n "$primary" ] || continue
      if grep -Fxq "$primary" "$seen" 2>/dev/null; then continue; fi
      echo "$primary" >> "$seen"
      count="$(list_worktrees "$repo" | grep -c . || true)"
      if [ "$count" -gt 1 ]; then
        echo "$primary"
      fi
    done
  rm -f "$seen"
}

# -------------------------------------------------------------- self-test ---

self_test() {
  local T pass=0 fail=0 out rc past repo
  T="$(mktemp -d)"
  past=$(( $(date +%s) - 30 * 86400 ))
  repo="$T/repo"

  # Sandbox the liveness-join state (heartbeats / claims / transcripts) so
  # this whole suite never reads or writes real operator state — the join
  # never fires against production data even for the pre-existing
  # scenarios below (a fixture worktree path never coincidentally matches a
  # real heartbeat's worktree_root, but sandboxing means this suite never
  # even LOOKS at real files to confirm that).
  export HARNESS_SELFTEST=1
  export HEARTBEAT_STATE_DIR="$T/hb"
  export COG_CLAIMS_DIR="$T/claims"
  export OBS_TRANSCRIPTS_ROOT="$T/tx"
  mkdir -p "$HEARTBEAT_STATE_DIR" "$COG_CLAIMS_DIR" "$OBS_TRANSCRIPTS_ROOT"

  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name "Self Test"
  git -C "$repo" symbolic-ref HEAD refs/heads/master
  echo base > "$repo/f.txt"
  git -C "$repo" add f.txt
  GIT_AUTHOR_DATE="@$past +0000" GIT_COMMITTER_DATE="@$past +0000" \
    git -C "$repo" -c commit.gpgsign=false commit -qm "init (30d ago)"

  # wt-safe: at master tip, clean, 30d old -> SAFE-PRUNE
  git -C "$repo" worktree add -q "$T/wt-safe" -b wt-safe >/dev/null 2>&1
  # wt-dirty: at master tip, 30d old, but has an untracked file -> HOLDS-CONTENT
  git -C "$repo" worktree add -q "$T/wt-dirty" -b wt-dirty >/dev/null 2>&1
  echo scratch > "$T/wt-dirty/untracked.txt"
  # wt-unique: clean + old, but carries a unique patch -> HOLDS-CONTENT
  git -C "$repo" worktree add -q "$T/wt-unique" -b wt-unique >/dev/null 2>&1
  echo unique > "$T/wt-unique/u.txt"
  git -C "$T/wt-unique" add u.txt
  GIT_AUTHOR_DATE="@$past +0000" GIT_COMMITTER_DATE="@$past +0000" \
    git -C "$T/wt-unique" -c commit.gpgsign=false commit -qm "unique patch (30d ago)"

  assert() { # $1 desc, $2 condition result (0 = pass)
    if [ "$2" = "0" ]; then
      pass=$(( pass + 1 )); echo "  PASS: $1"
    else
      fail=$(( fail + 1 )); echo "  FAIL: $1"
    fi
  }

  echo "[self-test] scenario 1-3 + 6: report classification"
  out="$("$0" "$repo" 2>&1)"; rc=$?
  assert "report exits 0" "$rc"
  echo "$out" | grep 'wt-safe' | grep -q 'SAFE-PRUNE'
  assert "safe-prune worktree detected (wt-safe -> SAFE-PRUNE)" "$?"
  echo "$out" | grep 'wt-dirty' | grep -q 'HOLDS-CONTENT'
  assert "dirty worktree NEVER classified safe (wt-dirty -> HOLDS-CONTENT)" "$?"
  echo "$out" | grep 'wt-unique' | grep -q 'HOLDS-CONTENT'
  assert "unique-patch worktree NEVER safe (wt-unique -> HOLDS-CONTENT)" "$?"
  # primary skip: exactly 3 classification rows (the 3 secondary worktrees)
  [ "$(echo "$out" | grep -c -E '(SAFE-PRUNE|HOLDS-CONTENT)$')" = "3" ]
  assert "primary worktree never listed as a classification row" "$?"

  echo "[self-test] scenario 4: --prune without WORKTREE_SWEEP_APPROVE=1 refuses"
  out="$(env -u WORKTREE_SWEEP_APPROVE "$0" --prune "$repo" 2>&1)"; rc=$?
  [ "$rc" = "3" ]
  assert "--prune without approval exits 3" "$?"
  [ -d "$T/wt-safe" ]
  assert "nothing removed without approval (wt-safe still present)" "$?"

  echo "[self-test] scenario 5: --prune with approval removes ONLY the safe one"
  out="$(WORKTREE_SWEEP_APPROVE=1 WORKTREE_SWEEP_LOG="$T/sweep.log" "$0" --prune "$repo" 2>&1)"; rc=$?
  assert "approved prune exits 0" "$rc"
  [ ! -d "$T/wt-safe" ]
  assert "SAFE-PRUNE worktree removed (wt-safe gone)" "$?"
  ! git -C "$repo" rev-parse --verify --quiet refs/heads/wt-safe >/dev/null 2>&1
  assert "SAFE-PRUNE branch deleted via branch -d (wt-safe ref gone)" "$?"
  [ -d "$T/wt-dirty" ] && [ -d "$T/wt-unique" ]
  assert "HOLDS-CONTENT worktrees untouched (wt-dirty + wt-unique remain)" "$?"
  git -C "$repo" rev-parse --verify --quiet refs/heads/wt-unique >/dev/null 2>&1
  assert "HOLDS-CONTENT branch untouched (wt-unique ref remains)" "$?"
  [ -d "$repo/.git" ] && [ -f "$repo/f.txt" ]
  assert "primary worktree never touched (repo + tracked file intact)" "$?"
  grep -q 'removed worktree=.*wt-safe' "$T/sweep.log" 2>/dev/null
  assert "removal logged to sweep log" "$?"

  echo "[self-test] bonus: --session-summary silent at <=5 worktrees"
  out="$("$0" --session-summary "$repo" 2>&1)"
  [ -z "$out" ]
  assert "--session-summary prints nothing for repo with <=5 worktrees" "$?"

  # ============================================================
  # --stranded suite: a DEDICATED fixture repo (the prune-suite's own
  # $repo/wt-safe above is already gone by this point — scenario 5 approved-
  # pruned it — so this suite builds its own independent repo+worktrees
  # rather than reusing partially-mutated fixtures).
  # ============================================================
  echo "[self-test] --stranded: build a dedicated fixture repo"
  local spast srepo
  spast=$(( $(date +%s) - 30 * 86400 ))
  srepo="$T/srepo"
  git init -q "$srepo"
  git -C "$srepo" config user.email test@example.com
  git -C "$srepo" config user.name "Self Test"
  git -C "$srepo" symbolic-ref HEAD refs/heads/master
  echo base > "$srepo/f.txt"
  git -C "$srepo" add f.txt
  GIT_AUTHOR_DATE="@$spast +0000" GIT_COMMITTER_DATE="@$spast +0000" \
    git -C "$srepo" -c commit.gpgsign=false commit -qm "init (30d ago)"

  # sw-safe: clean, at base tip, 30d old -> SAFE-PRUNE (never liveness-split)
  git -C "$srepo" worktree add -q "$T/sw-safe" -b sw-safe >/dev/null 2>&1
  # sw-dirty: untracked file -> HOLDS-CONTENT, dirty>0
  git -C "$srepo" worktree add -q "$T/sw-dirty" -b sw-dirty >/dev/null 2>&1
  echo scratch > "$T/sw-dirty/untracked.txt"
  # sw-unique: clean tree, but a committed-and-never-cherry-picked patch
  git -C "$srepo" worktree add -q "$T/sw-unique" -b sw-unique >/dev/null 2>&1
  echo unique > "$T/sw-unique/u.txt"
  git -C "$T/sw-unique" add u.txt
  GIT_AUTHOR_DATE="@$spast +0000" GIT_COMMITTER_DATE="@$spast +0000" \
    git -C "$T/sw-unique" -c commit.gpgsign=false commit -qm "unique patch (30d ago)"

  _write_hb() { # $1=session-id $2=worktree_root $3=last_activity_ts(ISO) $4=pid $5=marker_state
    local sid="$1" wtr="$2" ts="$3" pid="$4" marker="${5:-none}"
    cat > "$HEARTBEAT_STATE_DIR/${sid}.json" <<EOF
{"schema":1,"session_id":"${sid}","pid":${pid},"cwd":"${wtr}","repo_root":"${wtr}","worktree_root":"${wtr}","branch":"x","model":"sonnet","last_activity_ts":"${ts}","last_event":"turn-end","marker_state":"${marker}"}
EOF
  }
  _iso_minutes_ago() {
    local mins="$1" ts
    ts=$(( $(date -u +%s) - mins * 60 ))
    date -u -d "@${ts}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null && return 0
    date -u -j -f '%s' "${ts}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null
  }

  echo "[self-test] S-a/S-b: --stranded fires on unowned dirty + unowned unintegrated"
  out="$("$0" --stranded "$srepo" 2>&1)"
  echo "$out" | grep -q '\[stranded-work\]'
  assert "S-a/b: --stranded FIRES with no live owner" "$?"
  echo "$out" | grep -q 'sw-dirty'
  assert "S-a: dirty worktree with no owner -> ORPHANED" "$?"
  echo "$out" | grep -q 'sw-unique'
  assert "S-b: clean-but-unintegrated worktree with no owner -> ORPHANED (committed-but-never-cherry-picked strand caught by git cherry)" "$?"

  out="$("$0" --stranded --porcelain "$srepo" 2>&1)"
  [ "$(echo "$out" | grep -c '^ORPHANED-HOLDS-CONTENT')" = "2" ]
  assert "porcelain: 2 ORPHANED rows (sw-dirty + sw-unique), no header/table" "$?"
  ! echo "$out" | grep -q 'sw-safe'
  assert "porcelain: SAFE-PRUNE sw-safe never a porcelain row" "$?"

  echo "[self-test] S-d/S-f: repo with only a clean/old secondary -> silent"
  local srepo2
  srepo2="$T/srepo-onlysafe"
  git init -q "$srepo2"
  git -C "$srepo2" config user.email test@example.com
  git -C "$srepo2" config user.name "Self Test"
  git -C "$srepo2" symbolic-ref HEAD refs/heads/master
  echo base > "$srepo2/f.txt"
  git -C "$srepo2" add f.txt
  GIT_AUTHOR_DATE="@$spast +0000" GIT_COMMITTER_DATE="@$spast +0000" \
    git -C "$srepo2" -c commit.gpgsign=false commit -qm "init (30d ago)"
  git -C "$srepo2" worktree add -q "$T/sw-onlysafe" -b sw-onlysafe >/dev/null 2>&1

  out="$("$0" --stranded "$srepo2" 2>&1)"
  [ -z "$out" ]
  assert "S-d: repo whose only secondary is clean/old (SAFE-PRUNE) -> --stranded SILENT" "$?"
  out="$("$0" --stranded --porcelain "$srepo2" 2>&1)"
  [ -z "$out" ]
  assert "S-f: --stranded --porcelain on all-clean repo -> zero rows (doctor stays quiet)" "$?"

  echo "[self-test] S-c: crashed heartbeat still fires"
  local dead_pid
  ( : ) & dead_pid=$!
  wait "$dead_pid" 2>/dev/null
  _write_hb "sess-crashed" "$T/sw-dirty" "2020-01-01T00:00:00Z" "$dead_pid"
  out="$("$0" --stranded "$srepo" 2>&1)"
  echo "$out" | grep -q 'sw-dirty'
  assert "S-c: crashed heartbeat (dead pid) owning sw-dirty -> STILL ORPHANED (a dead heartbeat is not liveness)" "$?"
  echo "$out" | grep -q 'heartbeat=crashed'
  assert "S-c: liveness verdict reported as heartbeat=crashed" "$?"
  rm -f "$HEARTBEAT_STATE_DIR/sess-crashed.json"

  echo "[self-test] S-g: live heartbeat -> NOT flagged"
  _write_hb "sess-live" "$T/sw-dirty" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$$"
  out="$("$0" --stranded "$srepo" 2>&1)"
  ! echo "$out" | grep -q 'sw-dirty'
  assert "S-g: live heartbeat (fresh ts, alive pid) owning sw-dirty -> NOT flagged" "$?"
  rm -f "$HEARTBEAT_STATE_DIR/sess-live.json"

  echo "[self-test] S-h: mid-turn stale-heartbeat-but-fresh-transcript -> NOT flagged"
  _write_hb "sess-midturn" "$T/sw-dirty" "2020-01-01T00:00:00Z" "$$"
  printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-midturn.jsonl"
  out="$("$0" --stranded "$srepo" 2>&1)"
  ! echo "$out" | grep -q 'sw-dirty'
  assert "S-h: heartbeat old but transcript fresh (mid-turn) -> live, NOT flagged (tool-heavy-turn false-positive fix)" "$?"
  rm -f "$HEARTBEAT_STATE_DIR/sess-midturn.json" "$OBS_TRANSCRIPTS_ROOT/sess-midturn.jsonl"

  echo "[self-test] S-i: throttled owner (alive pid + API-error transcript tail) -> NOT flagged"
  _write_hb "sess-throttled" "$T/sw-dirty" "2020-01-01T00:00:00Z" "$$"
  printf '{"type":"system","subtype":"api_error","retryAttempt":1,"maxRetries":5,"retryInMs":1000}\n' > "$OBS_TRANSCRIPTS_ROOT/sess-throttled.jsonl"
  out="$("$0" --stranded "$srepo" 2>&1)"
  ! echo "$out" | grep -q 'sw-dirty'
  assert "S-i: throttled owner (alive pid, API-error transcript tail) -> NOT flagged" "$?"
  rm -f "$HEARTBEAT_STATE_DIR/sess-throttled.json" "$OBS_TRANSCRIPTS_ROOT/sess-throttled.jsonl"

  echo "[self-test] S-j: CONTINUING-marker grace (mode-b standing-by)"
  local dead_pid2 in_grace_ts past_grace_ts
  ( : ) & dead_pid2=$!
  wait "$dead_pid2" 2>/dev/null
  in_grace_ts="$(_iso_minutes_ago 45)"
  _write_hb "sess-continuing" "$T/sw-dirty" "$in_grace_ts" "$dead_pid2" "CONTINUING"
  out="$("$0" --stranded "$srepo" 2>&1)"
  ! echo "$out" | grep -q 'sw-dirty'
  assert "S-j: CONTINUING marker within grace (dead pid, 45m old, grace=90m) -> standing-by, NOT flagged" "$?"

  past_grace_ts="$(_iso_minutes_ago 120)"
  _write_hb "sess-continuing" "$T/sw-dirty" "$past_grace_ts" "$dead_pid2" "CONTINUING"
  out="$("$0" --stranded "$srepo" 2>&1)"
  echo "$out" | grep -q 'sw-dirty'
  assert "S-j: CONTINUING marker aged PAST grace (120m) -> flagged (wake deadline lapsed)" "$?"
  rm -f "$HEARTBEAT_STATE_DIR/sess-continuing.json"

  echo "[self-test] S-k: fresh claim ownership (repo-scoped)"
  local repo_id
  repo_id="$(_whs_repo_identity "$srepo")"
  cat > "$COG_CLAIMS_DIR/claim-same-repo.json" <<EOF
{"branch":"sw-dirty","worktree":"$T/sw-dirty","repo":"$repo_id","hostname":"selftest","iso_timestamp":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"}
EOF
  out="$("$0" --stranded "$srepo" 2>&1)"
  ! echo "$out" | grep -q 'sw-dirty'
  assert "S-k: fresh same-repo claim covering sw-dirty -> NOT flagged" "$?"
  rm -f "$COG_CLAIMS_DIR/claim-same-repo.json"

  cat > "$COG_CLAIMS_DIR/claim-foreign-repo.json" <<EOF
{"branch":"sw-dirty","worktree":"$T/sw-dirty","repo":"/somewhere/else/entirely/.git","hostname":"selftest","iso_timestamp":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"}
EOF
  out="$("$0" --stranded "$srepo" 2>&1)"
  echo "$out" | grep -q 'sw-dirty'
  assert "S-k: foreign-repo claim (repo id mismatch) -> still flagged (repo-scoping)" "$?"
  rm -f "$COG_CLAIMS_DIR/claim-foreign-repo.json"

  echo "[self-test] S-l: SELF + primary skip"
  out="$(cd "$T/sw-dirty" && "$0" --stranded "$srepo" 2>&1)"
  ! echo "$out" | grep -q 'sw-dirty'
  assert "S-l: invoking --stranded FROM inside sw-dirty (SELF) -> sw-dirty excluded" "$?"
  ! echo "$out" | grep -qF "$srepo"$'\t'
  assert "S-l: the primary checkout itself is never a classification row (existing primary-skip)" "$?"

  echo "[self-test] S-e: already-merged exclusion (git cherry + is-ancestor across all 4 refs)"
  # Simulate origin/master LAGGING a local merge: an explicit remote-
  # tracking ref pinned at the PRE-merge tip (resolve_base picks
  # origin/master FIRST, so git cherry alone would still see the merged
  # commit as '+' against this stale base) while local "master" races
  # ahead via a real merge. Only the is-ancestor-across-all-4-refs fallback
  # (which also checks local "master") can exclude it correctly.
  git -C "$srepo" update-ref refs/remotes/origin/master refs/heads/master
  ( cd "$srepo" && git merge --no-edit -q sw-unique ) >/dev/null 2>&1
  out="$("$0" --stranded "$srepo" 2>&1)"
  ! echo "$out" | grep -q 'sw-unique'
  assert "S-e: origin/master lags a LOCAL merge -> is-ancestor(master) fallback excludes sw-unique (git cherry alone against the stale base would false-flag it)" "$?"

  # ============================================================
  # REFORMULATION suite: subagent-transcript-mtime liveness for
  # agent-<id> worktrees (docs/harness-improvements/orphaned-worktree-
  # guard.md — the cry-wolf FP fix). Dedicated fixture worktrees whose
  # BASENAME starts with "agent-" (the harness's own dispatch-time naming
  # convention), each with a matching fixture transcript placed at the
  # REAL nested depth (<root>/<proj>/<sess>/subagents/agent-<id>.jsonl)
  # under the sandboxed OBS_TRANSCRIPTS_ROOT so this suite never reads
  # real transcript state either.
  # ============================================================
  echo "[self-test] REFORMULATION: build agent-<id> fixture worktrees"
  git -C "$srepo" worktree add -q "$T/agent-selftest-live" -b sw-agent-live >/dev/null 2>&1
  echo scratch > "$T/agent-selftest-live/untracked.txt"
  git -C "$srepo" worktree add -q "$T/agent-selftest-stale" -b sw-agent-stale >/dev/null 2>&1
  echo scratch > "$T/agent-selftest-stale/untracked.txt"

  _write_agent_tx() { # $1=agent_id $2=age_minutes_ago ("" = now/fresh)
    local aid="$1" age="$2" dir="$OBS_TRANSCRIPTS_ROOT/proj-x/sess-x/subagents" ts
    mkdir -p "$dir"
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' > "$dir/${aid}.jsonl"
    if [ -n "$age" ]; then
      ts=$(( $(date -u +%s) - age * 60 ))
      touch -d "@${ts}" "$dir/${aid}.jsonl" 2>/dev/null || \
        touch -t "$(date -u -r "$ts" '+%Y%m%d%H%M.%S' 2>/dev/null)" "$dir/${aid}.jsonl" 2>/dev/null || true
    fi
  }

  echo "[self-test] (a) agent-<id> worktree + FRESH transcript mtime -> NOT stranded"
  _write_agent_tx "agent-selftest-live" ""
  out="$("$0" --stranded "$srepo" 2>&1)"
  ! echo "$out" | grep -q 'agent-selftest-live'
  assert "(a) dirty agent-<id> worktree with a FRESH own-transcript mtime -> LIVE-OWNED, not stranded" "$?"

  echo "[self-test] (b) agent-<id> worktree + STALE transcript mtime (past AGENT_TX_FRESH_MIN) -> stranded"
  _write_agent_tx "agent-selftest-stale" 45
  out="$("$0" --stranded "$srepo" 2>&1)"
  echo "$out" | grep -q 'agent-selftest-stale'
  assert "(b) dirty agent-<id> worktree whose own-transcript mtime is 45m old (default AGENT_TX_FRESH_MIN=30) -> ORPHANED, stranded" "$?"
  echo "$out" | grep -q 'liveness=agent-transcript-stale'
  assert "(b) reported verdict is agent-transcript-stale (distinguished from generic no-heartbeat/claim)" "$?"

  echo "[self-test] (c) a NON-agent worktree still uses the heartbeat path unchanged, even with unrelated agent-*.jsonl fixtures present in the cache"
  _write_agent_tx "agent-unrelated-other-builder" ""
  _write_hb "sess-crashed-c" "$T/sw-dirty" "2020-01-01T00:00:00Z" "$dead_pid"
  out="$("$0" --stranded "$srepo" 2>&1)"
  echo "$out" | grep -q 'sw-dirty'
  assert "(c) non-agent-named worktree (sw-dirty) with a crashed heartbeat -> STILL flagged via the heartbeat path, unaffected by unrelated agent-transcript cache entries" "$?"
  ! echo "$out" | grep -q 'agent-unrelated-other-builder'
  assert "(c) the unrelated fixture agent transcript never itself produces a spurious row (no worktree named after it exists)" "$?"
  rm -f "$HEARTBEAT_STATE_DIR/sess-crashed-c.json"

  rm -rf "$T"
  echo ""
  echo "[self-test] $pass passed, $fail failed"
  [ "$fail" = "0" ] && return 0 || return 1
}

# ------------------------------------------------------------------- main ---

MODE="report"
PORCELAIN=0
REPOS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prune)           MODE="prune" ;;
    --session-summary) MODE="summary" ;;
    --stranded)        MODE="stranded" ;;
    --porcelain)       PORCELAIN=1 ;;
    --self-test)       self_test; exit $? ;;
    --help|-h)         sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)                echo "unknown flag: $1" >&2; exit 2 ;;
    *)                 REPOS="$REPOS
$1" ;;
  esac
  shift
done

if [ "$MODE" = "prune" ] && [ "${WORKTREE_SWEEP_APPROVE:-0}" != "1" ]; then
  echo "REFUSING --prune: WORKTREE_SWEEP_APPROVE=1 is not set." >&2
  echo "Per standing order, nothing is deleted without explicit operator approval;" >&2
  echo "the WORKTREE_SWEEP_APPROVE=1 env flag is that approval channel." >&2
  exit 3
fi

if [ -z "$(echo "$REPOS" | tr -d '[:space:]')" ]; then
  REPOS="$(discover_repos)"
  if [ -z "$REPOS" ]; then
    echo "no worktree-bearing repos found under $HOME/claude-projects" >&2
    exit 0
  fi
fi

ROWS_FILE="$(mktemp)"
STRANDED_ROWS_FILE="$(mktemp)"
trap 'rm -f "$ROWS_FILE" "$STRANDED_ROWS_FILE"' EXIT

echo "$REPOS" | grep -v '^$' | while read -r repo; do
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "skip: $repo is not a git repo" >&2
    continue
  fi
  sweep_repo "$repo" "$MODE"
done

if [ "$MODE" = "stranded" ]; then
  _emit_stranded
fi

exit 0
