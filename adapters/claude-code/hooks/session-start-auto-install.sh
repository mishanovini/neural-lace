#!/bin/bash
# NEURAL-LACE-HOOK
# session-start-auto-install.sh — Continuous live ~/.claude/ sync from canonical NL master.
#
# THE GAP THIS CLOSES
#   When NL gets a new hook/script/settings change merged to master, machines
#   that pull NL get the *repo source* updated but their *live ~/.claude/* stays
#   stale until someone manually runs install.sh. install.sh is a one-time
#   per-machine ceremony, not a continuous sync — so harness changes silently
#   fail to propagate across machines (e.g. a new hook just never fires).
#
# WHAT IT DOES (every SessionStart, early in the chain)
#   1. Discovers the canonical NL checkout (config -> candidate paths -> cwd).
#   2. Best-effort bounded `git fetch origin master` so the canonical ref is fresh.
#   3. Reads canonical file CONTENT from the freshest fetched ref
#      (origin/master, fallback local master, fallback HEAD) via `git show`,
#      NOT the working tree.
#   4. Syncs hooks/*.sh + scripts/*.sh into live ~/.claude/: install if missing,
#      install if differing (master-wins, with a timestamped backup first).
#   5. Surgically additive-merges any missing canonical settings.json hook-entries
#      (matched by .command; validate-before-atomic-swap; never removes/reorders
#      live entries) and self-wires its own SessionStart entry at the FRONT.
#   6. Logs actions to ~/.claude/state/auto-install-log-<ts>.txt + a one-line
#      stderr summary. Idempotent, fast in the steady state, exits 0 always.
#   7. Self-sync guard (SELF-SYNC-01, 2026-07-29): on a machine where live
#      ~/.claude/ subdirs are SYMLINKS back into this repo, a sync target
#      can resolve, through that symlink, onto the very repo file step 3
#      just read FROM -- overwriting newer committed-but-unmerged branch
#      work with older origin/master content. Every write/delete path below
#      (file install/update, stale-flat-skill prune, settings.json merge)
#      checks this FIRST and skips rather than overwrite. See the guard's
#      source block (search SELF-SYNC-01) for the skip-vs-louder decision
#      and docs/decisions/065-self-sync-guard-signal-level.md.
#   8. Kill-switch (2026-07-29, added after the self-sync guard fired to close
#      TWO incidents in one day -- the guard closes the known hole, this is
#      the seatbelt for a hole not yet found): if
#      `$LIVE_DIR/local/no-auto-install` exists, main() returns immediately,
#      before discovering a checkout, fetching, or touching anything --
#      logged once to stderr, naming the marker path. This is a MARKER FILE,
#      not an env var, because an operator reacting mid-incident is not
#      "mid-session" in a shell that could export one, and the fix must not
#      require touching ~/.claude/settings.json (machine-local config this
#      hook cannot safely self-modify). `rm` the marker file to re-enable.
#
# WHY READ THE origin/master REF, NOT THE WORKING TREE
#   The install footgun is "rebuild live from whatever checkout you run in" — a
#   stale or feature-branch checkout downgrades live. A SessionStart hook runs in
#   checkouts that are frequently on feature branches. Reading
#   `git show origin/master:<path>` is branch-independent and always installs the
#   freshest *fetched canonical* content, sidestepping the footgun by construction
#   and composing with the "don't auto-pull" posture (we never touch the tree).
#
# WHY master-wins FOR HOOKS/SCRIPTS BUT additive-merge FOR settings.json
#   Per rules/harness-maintenance.md, canonical hooks/scripts have NO legitimate
#   machine-local drift (edit repo -> sync to live; never keep divergent live
#   copies). So canonical always wins for those (a differing live copy is stale).
#   Only settings.json + ~/.claude/local/ carry legitimate machine-local state, so
#   settings.json gets a conservative additive-only jq-merge that never removes a
#   live entry, with validate-before-atomic-swap so corruption cannot arise.
#
# BOOTSTRAP CAVEAT (honest; not a false promise)
#   The hook cannot run on a brand-new machine until it is itself present + wired
#   in live ~/.claude/. The first install.sh run per new machine lands the hook +
#   its wiring; every subsequent change — including future versions of this hook —
#   then self-propagates automatically.
#
# Self-test: invoke with --self-test to exercise the scenario matrix (24 cases;
# was already stale at 18 before this count -- scenarios 19-22 are SELF-SYNC-01,
# 23-24 are the kill-switch).

set -u

# ============================================================
# Constants / overrides (overrides exist for the self-test)
# ============================================================

FETCH_TIMEOUT_SECONDS="${FETCH_TIMEOUT_SECONDS:-10}"
# LIVE_DIR_OVERRIDE lets the self-test point "live ~/.claude" at a temp dir.
LIVE_DIR="${LIVE_DIR_OVERRIDE:-$HOME/.claude}"
# Canonical surfaces synced master-wins. Executable surfaces (hooks/scripts =
# .sh) AND content surfaces (agents/rules/templates/skills/doctrine = .md) are
# all pure harness content with no legitimate machine-local drift (per
# rules/harness-maintenance.md), so canonical always wins. Live-only files are
# NEVER deleted — only install-if-missing / update-if-differing. (Extended
# 2026-06-03: agents/rules/templates/skills were previously install.sh-only, so
# they silently drifted on every machine until a manual install — HARNESS-GAP.
# Extended Wave-C C.5: doctrine/ added as the new canonical home for doctrine
# content moved out of rules/ — never-delete semantics are fine here; canon
# stops carrying the old rules/*.md content after the master merge, and
# install.sh's rules-prune step is the one place stale rules/*.md get removed.
# Extended T17 remedy R1 (2026-08-04): config/ added -- dispatch-chain-gate.sh
# reads config/model-policy.json + config/g2-grandfather-slugs.txt SCRIPT-
# LOCATION-RELATIVE to its own installed location, by explicit design, and
# neither install.sh's dir loop nor this SYNC_SUBDIRS list deployed config/ at
# all before this fix -- every installed machine's G2 gate silently degraded
# to a permanent no-op. config/ is the FIRST heterogeneous-extension subdir
# (.json/.txt/.md/.example) -- see _subdir_ext below.)
SYNC_SUBDIRS="hooks scripts agents rules templates skills doctrine config"

# Review-before-deploy gate (harness-governance-batch-2026-07-15, task 2;
# design: docs/design-notes/review-record-primitive.md, Amendment F). This
# hook is fail-open BY PLATFORM CONTRACT (always exits 0 -- a background
# SessionStart script must never wedge a session), so its posture here is
# SKIP the uncovered file + WARN LOUDLY, never a hard block. Contrast with
# install.sh (operator present), which hard-blocks the whole run. Sourced
# best-effort: if the lib is missing (a checkout that predates this batch),
# every file syncs with the pre-existing, ungated behavior.
# shellcheck source=lib/review-record-gate-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/review-record-gate-lib.sh" 2>/dev/null || true
N_REVIEW_SKIPPED=0

# --- self-sync guard (SELF-SYNC-01, shared with install.sh) --------------
# PROVEN data loss, 2026-07-29: on a SYMLINK-based install, a live
# ~/.claude/ subdir (hooks/scripts/agents/...) is a symlink back into this
# repo's adapters/claude-code/. sync_canonical_files() below reads canonical
# content from $ref (origin/master) into a temp file and cp's it onto
# $target -- but when $target resolves, THROUGH the symlink, onto the very
# repo file this checkout is reading FROM, that cp overwrites committed
# branch work with older origin/master content. 27 files were reverted this
# way in one run, including hooks/model-pin-gate.sh (265 lines -> its
# pre-change state). See .claude/state/observed-errors.md (2026-07-29
# 09:41 entry) and install.sh's SELF-SYNC-01 fix (same root cause, a
# different code path: `rm -rf` there vs. overwrite-with-stale-content
# here).
#
# resolve_real_path / _sync_self_check / _resolves_into_dir are SHARED with
# install.sh (hooks/lib/self-sync-guard.sh) rather than forked, so a future
# fix to the path-resolution logic cannot drift between the two carriers.
#
# SKIP vs LOUDER (decision, see docs/decisions/065-self-sync-guard-signal-level.md):
# install.sh's guard prints a full explanatory block per skipped call
# because an operator is present, watching stdout, for a ceremony that runs
# rarely. This hook runs UNATTENDED on every SessionStart; on a
# symlinked-install machine (this Mac, by operator directive) EVERY
# canonical file in every synced subdir will legitimately self-sync-skip on
# EVERY session, forever. A per-file echo block at that frequency is either
# ignored (defeats "louder") or drowns every other SessionStart signal
# (defeats usability) -- so a silent, install.sh-style skip is *worse* here,
# not better: the alternative is a wall of repeated text nobody reads,
# which is its own way of teaching the operator to ignore this hook's
# stderr entirely. The chosen middle ground: fold every skip into a
# dedicated counter (N_SELF_SYNC_SKIPPED) that appears in the ONE-LINE
# summary this hook ALREADY prints on every run (both to stderr and to the
# run log), so the signal is always present, at a fixed cost of one number,
# rather than either fully silent or unboundedly loud. Each individual skip
# still gets a full-detail line in the run log (state/auto-install-log-*)
# for forensic replay, just not on stderr where it would spam every
# session.
# shellcheck source=lib/self-sync-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/self-sync-guard.sh" 2>/dev/null || true
if ! declare -F resolve_real_path >/dev/null 2>&1 || ! declare -F _sync_self_check >/dev/null 2>&1; then
  echo "session-start-auto-install: WARN hooks/lib/self-sync-guard.sh missing -- self-sync guard DISABLED, syncs are UNGUARDED against symlinked-install data loss (SELF-SYNC-01)" >&2
  # Fail-open shim matches this hook's platform contract (never block a
  # session start) but must not silently pretend the guard ran: _sync_self_check
  # always reports "not the same" (pre-fix behavior) and _resolves_into_dir
  # always reports "not inside", so callers below proceed exactly as they did
  # before this guard existed.
  _sync_self_check() { return 1; }
  _resolves_into_dir() { return 1; }
fi
N_SELF_SYNC_SKIPPED=0

# --- portable bounded subprocess (plan macos-portability-2026-07, M3) -----
# nl_run_bounded bounds ensure_fresh_origin_master's network fetch on EVERY
# platform, including stock macOS where GNU `timeout` does not exist.
# Defensive source + loud shim: a partial install degrades visibly rather
# than dropping the bound in silence.
# shellcheck source=lib/portable-timeout.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/portable-timeout.sh" 2>/dev/null || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local s="${1:-0}"; shift 2>/dev/null || true
    echo "session-start-auto-install: WARN hooks/lib/portable-timeout.sh missing — running UNBOUNDED (wanted ${s}s): ${1:-<none>}" >&2
    [ "$#" -gt 0 ] || return 2
    "$@"
  }
fi

# Per-subdir canonical file extension(s): executable (.sh) vs content (.md)
# vs config (heterogeneous -- .json/.txt/.md/.example; T17 remedy R1,
# 2026-08-04). Space-separated when a subdir ships more than one type; every
# caller (sync_canonical_files' ls-tree filter, its live-side drift glob, and
# the chmod-executable check) must treat the result as a SET, not a scalar.
_subdir_ext() {
  case "$1" in
    hooks|scripts) printf 'sh' ;;
    config)        printf 'json txt md example' ;;
    *)             printf 'md' ;;
  esac
}
# Candidate NL checkout locations (first valid wins). These are GENERIC defaults;
# a machine whose checkout lives elsewhere (e.g. a path with spaces) names it in
# ~/.claude/local/nl-checkout-path.txt (per-machine config, gitignored — never
# ship a specific machine path in the kit). The cwd walk-up is the final fallback.
# The shared lib/nl-paths.sh resolver's probe list is consulted first (step 1.5
# below); these generic per-scheme guesses are additional siblings for
# checkouts that don't match nl-paths.sh's own short probe list.
NL_CANDIDATES=(
  "$HOME/dev/neural-lace"
  "$HOME/code/neural-lace"
  "$HOME/src/neural-lace"
  "$HOME/projects/neural-lace"
  "$HOME/neural-lace"
)

# Action counters (reset per run)
N_INSTALLED=0
N_UPDATED=0
N_UNCHANGED=0
N_SETTINGS_ADDED=0
N_DRIFT=0

# ============================================================
# Helpers
# ============================================================

# A directory is a valid NL checkout if it carries the installer sentinel and
# is a git work tree.
_is_valid_nl_checkout() {
  local d="$1"
  [ -n "$d" ] || return 1
  [ -f "$d/adapters/claude-code/install.sh" ] || return 1
  head -2 "$d/adapters/claude-code/install.sh" 2>/dev/null | grep -q "NEURAL-LACE-INSTALLER" || return 1
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  return 0
}

# Echo the absolute path of the canonical NL checkout, or empty.
discover_nl_checkout() {
  # 1. Explicit override (self-test / power user).
  if [ -n "${NL_CHECKOUT_OVERRIDE:-}" ] && _is_valid_nl_checkout "$NL_CHECKOUT_OVERRIDE"; then
    printf '%s\n' "$NL_CHECKOUT_OVERRIDE"
    return 0
  fi
  # 1.5. $NL_REPO_ROOT env var (the shared lib/nl-paths.sh convention — see
  #      B.2). Explicit-only here (NOT the full nl_repo_root() git-derived /
  #      probe-list fallback, which always resolves to whatever checkout this
  #      hook file itself lives in and would defeat step 4's cwd-based
  #      "genuinely no other checkout available" detection).
  if [ -n "${NL_REPO_ROOT:-}" ] && _is_valid_nl_checkout "$NL_REPO_ROOT"; then
    printf '%s\n' "$NL_REPO_ROOT"
    return 0
  fi
  # 2. Per-machine config file naming the checkout path (this hook's own
  #    config, plus the shared lib/nl-paths.sh config as a synonym so a
  #    machine configured for one resolver is recognized by both).
  local cfg="$LIVE_DIR/local/nl-checkout-path.txt"
  if [ -f "$cfg" ]; then
    local line
    line=$(grep -vE '^[[:space:]]*(#|$)' "$cfg" 2>/dev/null | head -1)
    # strip surrounding whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [ -n "$line" ] && _is_valid_nl_checkout "$line"; then
      printf '%s\n' "$line"
      return 0
    fi
  fi
  local shared_cfg="$LIVE_DIR/local/nl-repo-path"
  if [ -f "$shared_cfg" ]; then
    local sline
    sline=$(head -1 "$shared_cfg" 2>/dev/null)
    sline="${sline#"${sline%%[![:space:]]*}"}"
    sline="${sline%"${sline##*[![:space:]]}"}"
    if [ -n "$sline" ] && _is_valid_nl_checkout "$sline"; then
      printf '%s\n' "$sline"
      return 0
    fi
  fi
  # 3. Candidate paths.
  local cand
  for cand in "${NL_CANDIDATES[@]}"; do
    if _is_valid_nl_checkout "$cand"; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  # 4. cwd-fallback: walk up from $PWD looking for an NL checkout root.
  local dir="$PWD"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if _is_valid_nl_checkout "$dir"; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  printf '%s\n' ""
  return 0
}

# Best-effort bounded fetch of origin/master. Never blocks > the bound.
# Skippable.
#
# The bound is load-bearing: this is a SessionStart hook, so an unbounded
# network fetch against a hung remote stalls the start of every session on
# the machine. The previous `command -v timeout || <fetch anyway>` guard
# dropped the bound entirely on stock macOS (no GNU coreutils, hence no
# `timeout`). nl_run_bounded keeps it on every platform — see
# hooks/lib/portable-timeout.sh, sourced below the function definitions.
ensure_fresh_origin_master() {
  local nl="$1"
  [ "${AUTO_INSTALL_NO_FETCH:-0}" = "1" ] && return 0
  git -C "$nl" remote 2>/dev/null | grep -q '^origin$' || return 0
  nl_run_bounded "$FETCH_TIMEOUT_SECONDS" git -C "$nl" fetch origin master --quiet >/dev/null 2>&1 || true
  return 0
}

# Echo the freshest canonical ref that resolves, or empty.
pick_source_ref() {
  local nl="$1" ref
  for ref in origin/master master HEAD; do
    if git -C "$nl" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      printf '%s\n' "$ref"
      return 0
    fi
  done
  printf '%s\n' ""
  return 0
}

# Append one line to the run log (created lazily).
_log() {
  printf '%s\n' "$1" >> "$LOG_FILE" 2>/dev/null || true
}

# Compare two files for CONTENT equality, ignoring CRLF-vs-LF line endings.
# Rationale: install.sh cp's from the (CRLF) working tree on Windows; this hook
# installs the (LF) git blob. A byte-cmp would treat those as "different" forever
# and the two installers would perpetually re-update each other. Comparing modulo
# '\r' means we only re-install on a GENUINE content change. Returns 0 if same.
_content_same() {
  cmp -s "$1" "$2" && return 0
  diff -q <(tr -d '\r' < "$1" 2>/dev/null) <(tr -d '\r' < "$2" 2>/dev/null) >/dev/null 2>&1
}

# Sync canonical files of one subdir (hooks|scripts=.sh, agents|rules|
# templates|skills=.md, config=.json/.txt/.md/.example) into live. master-
# wins. Args: nl_dir, ref, subdir
sync_canonical_files() {
  local nl="$1" ref="$2" subdir="$3"
  local live_sub="$LIVE_DIR/$subdir"
  # exts is a SET (space-separated, may be multiple -- config/ ships
  # heterogeneous file types; every other subdir today is single-extension,
  # but the code below never assumes that). ext_pat is the same set as an
  # ERE alternation for the ls-tree filter below.
  local exts; exts=$(_subdir_ext "$subdir")
  local ext_pat; ext_pat=$(printf '%s' "$exts" | tr ' ' '|')
  mkdir -p "$live_sub" 2>/dev/null || true

  # Canonical paths for this subdir at the ref (extension SET per subdir),
  # RELATIVE to the subdir. `-r` (recursive) is required: skills are
  # directory-form (`skills/<name>/SKILL.md` — the only form the Skill tool
  # registers; flat `skills/<name>.md` is silently non-invocable, see
  # docs/discoveries/2026-06-02-flat-md-skills-not-skill-tool-invocable.md).
  # A non-recursive ls-tree lists `<name>` as a tree entry with no .md
  # extension and silently skips every directory-form skill. Recursion also
  # picks up nested content in other subdirs (e.g. hooks/lib/*.sh) that the
  # flat listing previously missed.
  local canon_list
  canon_list=$(git -C "$nl" ls-tree -r --name-only "$ref" "adapters/claude-code/$subdir/" 2>/dev/null \
    | grep -E "\\.(${ext_pat})\$" | sed "s#^adapters/claude-code/$subdir/##" | sort -u)
  [ -z "$canon_list" ] && return 0

  local b tmp target
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    tmp=$(mktemp 2>/dev/null) || continue
    if ! git -C "$nl" show "$ref:adapters/claude-code/$subdir/$b" > "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      continue
    fi
    target="$live_sub/$b"
    mkdir -p "$(dirname "$target")" 2>/dev/null || true

    local full_rel="$subdir/$b"

    # SELF-SYNC-01: bail BEFORE any diff/copy logic below. When $target
    # resolves (through a symlinked live subdir) onto the very repo file
    # this loop is reading FROM ($nl/adapters/claude-code/$full_rel), the
    # cp below would overwrite that repo file's newer working-tree content
    # with $ref's (older) content -- exactly how 27 files were reverted on
    # 2026-07-29. See the header for the skip-vs-louder rationale.
    local shared_path
    if shared_path="$(_sync_self_check "$nl/adapters/claude-code/$full_rel" "$target" 2>/dev/null)"; then
      N_SELF_SYNC_SKIPPED=$((N_SELF_SYNC_SKIPPED + 1))
      _log "SELF-SYNC SKIP: $full_rel -- live path IS the repo file on disk ($shared_path); symlinked install, nothing to deploy (SELF-SYNC-01, not an error)"
      rm -f "$tmp"
      continue
    fi

    local is_missing=0 is_diff=0
    if [ ! -e "$target" ]; then
      is_missing=1
    elif ! _content_same "$tmp" "$target"; then
      is_diff=1
    fi

    if [ "$is_missing" -eq 1 ] || [ "$is_diff" -eq 1 ]; then
      if declare -F rrg_in_surface >/dev/null 2>&1 && rrg_in_surface "$full_rel"; then
        local rsha
        rsha=$(rrg_blob_sha_of_file "$tmp" 2>/dev/null)
        if ! rrg_is_covered "$nl" "$ref" "adapters/claude-code/$full_rel" "$rsha"; then
          N_REVIEW_SKIPPED=$((N_REVIEW_SKIPPED + 1))
          _log "REVIEW-GATE SKIP: $full_rel left un-synced (stale-not-blocked) -- no PASS harness-change-review record covers blob_sha ${rsha:-<unresolved>}"
          echo "[auto-install] REVIEW-GATE WARN: $full_rel changed but has NO PASS harness-change-review record -- SKIPPING this file (stale-not-blocked; run install.sh for the hard-block/authoritative path). See doctrine/review-before-deploy.md." >&2
          rm -f "$tmp"
          continue
        fi
      fi
    fi

    # Per-FILE extension (not per-subdir "$ext"): config/ ships a set, and
    # only a genuine .sh member of that set (none today, but the check must
    # be file-accurate, not subdir-accurate) should ever get +x.
    local b_ext="${b##*.}"

    if [ "$is_missing" -eq 1 ]; then
      cp "$tmp" "$target" 2>/dev/null && { [ "$b_ext" = sh ] && chmod +x "$target" 2>/dev/null; :; }
      N_INSTALLED=$((N_INSTALLED + 1))
      _log "installed $subdir/$b (was missing)"
    elif [ "$is_diff" -eq 1 ]; then
      # master-wins, but back up the prior live copy first ($b may be nested).
      mkdir -p "$BACKUP_DIR/$subdir/$(dirname "$b")" 2>/dev/null || true
      cp "$target" "$BACKUP_DIR/$subdir/$b" 2>/dev/null || true
      cp "$tmp" "$target" 2>/dev/null && { [ "$b_ext" = sh ] && chmod +x "$target" 2>/dev/null; :; }
      N_UPDATED=$((N_UPDATED + 1))
      _log "updated $subdir/$b (backed up prior copy to $(basename "$BACKUP_DIR")/$subdir/)"
    else
      N_UNCHANGED=$((N_UNCHANGED + 1))
    fi
    rm -f "$tmp"
  done <<< "$canon_list"

  # Count live files NOT in canonical (informational drift; never touched —
  # with ONE exception below for migrated flat skills). Loops over every
  # extension in the SET (config/ has more than one; every other subdir's
  # set today is a single element, so this is a no-behavior-change
  # generalization for them).
  local f base one_ext
  for one_ext in $exts; do
  for f in "$live_sub"/*."$one_ext"; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    if ! printf '%s\n' "$canon_list" | grep -qx "$base"; then
      # Flat-skill migration prune (2026-07): a live flat `skills/<name>.md`
      # whose canonical twin is now directory-form `skills/<name>/SKILL.md`
      # is a stale pre-migration remnant, not operator drift — the Skill tool
      # never registers it, so it is dead weight that shadows nothing. Back
      # it up, then remove. Files with NO canonical twin in either form are
      # still counted as drift and never touched.
      if [ "$subdir" = "skills" ] \
         && printf '%s\n' "$canon_list" | grep -qx "${base%.md}/SKILL.md"; then
        # SELF-SYNC-01: this is a DELETE path (`rm -f "$f"`), the same class
        # of hazard as sync_canonical_files' cp above. If $f resolves (via a
        # symlinked live skills/) onto a file actually living inside the
        # repo, this would delete a repo file, not a stale live copy.
        if _resolves_into_dir "$f" "$nl/adapters/claude-code" 2>/dev/null; then
          N_SELF_SYNC_SKIPPED=$((N_SELF_SYNC_SKIPPED + 1))
          _log "SELF-SYNC SKIP: prune of $subdir/$base skipped -- live path resolves into the repo (symlinked install); would delete a repo file, not a stale live copy (SELF-SYNC-01)"
          continue
        fi
        mkdir -p "$BACKUP_DIR/$subdir" 2>/dev/null || true
        cp "$f" "$BACKUP_DIR/$subdir/$base" 2>/dev/null || true
        rm -f "$f" 2>/dev/null || true
        _log "pruned stale flat skills/$base (canonical is now skills/${base%.md}/SKILL.md; backed up)"
        continue
      fi
      N_DRIFT=$((N_DRIFT + 1))
    fi
  done
  done
  return 0
}

# Surgical additive-merge of missing canonical settings.json hook-entries.
# Args: template_json_path, live_settings_path, nl_checkout_dir
merge_settings() {
  local template="$1" live="$2" nl="$3"

  if ! command -v jq >/dev/null 2>&1; then
    _log "settings: jq unavailable — skipped settings merge (file sync unaffected)"
    return 0
  fi
  if [ ! -f "$template" ]; then
    _log "settings: template not found at $template — skipped"
    return 0
  fi
  if [ ! -f "$live" ] || ! jq empty "$live" >/dev/null 2>&1; then
    _log "settings: live settings.json missing or invalid JSON — left untouched"
    return 0
  fi
  if ! jq empty "$template" >/dev/null 2>&1; then
    _log "settings: template settings.json invalid JSON — skipped"
    return 0
  fi

  local events="PreToolUse PostToolUse Stop SessionStart UserPromptSubmit TaskCreated TaskCompleted SubagentStop SubagentStart"
  local work
  work=$(mktemp 2>/dev/null) || return 0
  cp "$live" "$work" 2>/dev/null || { rm -f "$work"; return 0; }

  local added_total=0
  local event t_len i entry entry_cmds live_cmds is_new self_wire
  for event in $events; do
    t_len=$(jq -r ".hooks.\"$event\" // [] | length" "$template" 2>/dev/null)
    [[ "$t_len" =~ ^[0-9]+$ ]] || continue
    [ "$t_len" -eq 0 ] && continue
    i=0
    while [ "$i" -lt "$t_len" ]; do
      # The canonical top-level entry object {matcher, hooks:[...]}.
      entry=$(jq -c ".hooks.\"$event\"[$i]" "$template" 2>/dev/null)
      # Its inner command strings.
      entry_cmds=$(printf '%s' "$entry" | jq -r '.hooks[]?.command // empty' 2>/dev/null)
      # Live command set for this event.
      live_cmds=$(jq -r ".hooks.\"$event\" // [] | .[] | .hooks[]?.command // empty" "$work" 2>/dev/null)
      # is_new = none of entry's commands appear in live.
      is_new=1
      local c
      while IFS= read -r c; do
        [ -z "$c" ] && continue
        if printf '%s\n' "$live_cmds" | grep -Fxq "$c"; then
          is_new=0
          break
        fi
      done <<< "$entry_cmds"

      if [ "$is_new" -eq 1 ]; then
        # Self-wire (auto-install entry into SessionStart) -> prepend; else append.
        self_wire=0
        if [ "$event" = "SessionStart" ] && printf '%s' "$entry_cmds" | grep -q "session-start-auto-install.sh"; then
          self_wire=1
        fi
        local merged
        if [ "$self_wire" -eq 1 ]; then
          merged=$(jq --argjson e "$entry" ".hooks.\"$event\" = ([\$e] + (.hooks.\"$event\" // []))" "$work" 2>/dev/null)
        else
          merged=$(jq --argjson e "$entry" ".hooks.\"$event\" = ((.hooks.\"$event\" // []) + [\$e])" "$work" 2>/dev/null)
        fi
        if [ -n "$merged" ] && printf '%s' "$merged" | jq empty >/dev/null 2>&1; then
          printf '%s' "$merged" > "$work"
          added_total=$((added_total + 1))
        fi
      fi
      i=$((i + 1))
    done
  done

  if [ "$added_total" -gt 0 ]; then
    # SELF-SYNC-01: on a symlinked install where the WHOLE ~/.claude tree
    # (not just a subdir) is a symlink into the repo, $live can resolve into
    # adapters/claude-code/ too. The atomic `mv "$work" "$live"` below would
    # then silently create/overwrite a file inside the repo's own tree
    # rather than the machine's live settings. Defense in depth: $live has
    # no distinct "source of truth" to be reverted TO the way hooks/scripts
    # do (there is no settings.json.template counterpart named settings.json
    # in the repo), but refusing the write when the destination resolves
    # into the repo keeps this path's blast radius identical in kind to
    # every other write this hook performs.
    if [ -n "$nl" ] && _resolves_into_dir "$live" "$nl/adapters/claude-code" 2>/dev/null; then
      N_SELF_SYNC_SKIPPED=$((N_SELF_SYNC_SKIPPED + 1))
      _log "SELF-SYNC SKIP: settings merge skipped -- live settings.json resolves into the repo (symlinked install) (SELF-SYNC-01)"
      rm -f "$work"
      return 0
    fi
    # Validate-before-atomic-swap: corruption cannot arise.
    if jq empty "$work" >/dev/null 2>&1; then
      mkdir -p "$BACKUP_DIR" 2>/dev/null || true
      cp "$live" "$BACKUP_DIR/settings.json" 2>/dev/null || true
      mv "$work" "$live" 2>/dev/null || { rm -f "$work"; return 0; }
      N_SETTINGS_ADDED=$added_total
      _log "settings: added $added_total canonical hook-entr$([ "$added_total" -eq 1 ] && echo y || echo ies) (live drift preserved; prior backed up)"
      return 0
    fi
  fi
  rm -f "$work"
  return 0
}

# ============================================================
# Main
# ============================================================

main() {
  # --- Machine-local kill-switch (2026-07-29, second occurrence of SELF-SYNC-01) ---
  # PROVEN: this hook overwrote committed branch work TWICE on 2026-07-29 (09:41:43,
  # 27 files; again ~11:0x, 39 files) via the same symlinked-topology defect the
  # self-sync guard below now closes. Between the two incidents there was NO way for
  # the operator watching it happen to stop it -- no env var, no marker, nothing
  # short of hand-editing ~/.claude/settings.json's SessionStart chain (machine-local
  # config this session cannot safely touch). A deploy carrier that can silently
  # destroy work and cannot be turned off by the person watching it happen is itself
  # a defect, independent of whatever bug it's currently running with. This is the
  # seatbelt for a self-sync-guard hole not yet found, not a substitute for the guard.
  #
  # A MARKER FILE, not an env var: an env var set interactively does not survive
  # into this hook's own separate SessionStart-invoked process, and an operator
  # reacting mid-incident is not "mid-session" in the shell that would need to
  # export it. `$LIVE_DIR/local/` is real machine-local state (gitignored, never
  # synced by this hook itself, never a symlink target of anything this hook
  # touches) -- exactly the right place for a per-machine off-switch.
  if [ -e "$LIVE_DIR/local/no-auto-install" ]; then
    echo "[auto-install] KILL-SWITCH: $LIVE_DIR/local/no-auto-install exists -- skipping ALL sync/prune/settings-merge work this run. Remove that file to re-enable." >&2
    return 0
  fi

  local nl ref
  nl=$(discover_nl_checkout)
  if [ -z "$nl" ]; then
    echo "[auto-install] no NL checkout found — skipping (set $LIVE_DIR/local/nl-checkout-path.txt to enable)" >&2
    return 0
  fi

  # --- Single-flight debounce (SessionStart fork-storm prevention) ----------
  # If another session already ran auto-install within the last ~2 min, SKIP:
  # it synced the shared ~/.claude, which covers this session too. This kills
  # the concurrent-SessionStart CreateProcess storm (measured 34->81 bash.exe,
  # MsMpEng pinning a core) at its biggest source — the git fetch + full sync.
  # Fail-open (a broken lock never blocks a start). Keyed to LIVE_DIR so the
  # self-test's temp LIVE_DIR isolates the stamp; bypassed via SSF_DISABLE=1.
  # Ref: docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md rec 2
  #      (SESSIONSTART-SINGLEFLIGHT-01).
  # shellcheck source=lib/sessionstart-singleflight.sh
  source "$(dirname "${BASH_SOURCE[0]}")/lib/sessionstart-singleflight.sh" 2>/dev/null || true
  if declare -F ss_singleflight >/dev/null 2>&1; then
    if ! SSF_STATE_DIR="$LIVE_DIR/state/singleflight" ss_singleflight "auto-install" 120; then
      echo "[auto-install] another session synced within ~2 min — skipping (shared ~/.claude is already fresh)" >&2
      return 0
    fi
  fi

  ensure_fresh_origin_master "$nl"
  ref=$(pick_source_ref "$nl")
  if [ -z "$ref" ]; then
    echo "[auto-install] NL checkout at $nl has no master/HEAD ref — skipping" >&2
    return 0
  fi

  AUTO_INSTALL_TS="${AUTO_INSTALL_TS_OVERRIDE:-$(date +%Y%m%d-%H%M%S)}"
  BACKUP_DIR="$LIVE_DIR/.backup-auto-install-$AUTO_INSTALL_TS"
  LOG_FILE="$LIVE_DIR/state/auto-install-log-$AUTO_INSTALL_TS.txt"
  mkdir -p "$LIVE_DIR/state" 2>/dev/null || true

  local sub
  for sub in $SYNC_SUBDIRS; do
    sync_canonical_files "$nl" "$ref" "$sub"
  done

  # settings.json merge: template is the canonical wiring source from the same ref.
  # Review-before-deploy gate (harness-review REFORMULATE fixup, finding
  # 1b): the template is itself an in-surface file whose CONTENT drives
  # every hook-wiring merge_settings applies -- gate it the same way a
  # per-file sync is gated, skipping the whole merge (never partially) with
  # the same loud WARN pattern when it's uncovered.
  local tmpl
  tmpl=$(mktemp 2>/dev/null)
  if [ -n "$tmpl" ] && git -C "$nl" show "$ref:adapters/claude-code/settings.json.template" > "$tmpl" 2>/dev/null; then
    local tmpl_gated=1
    if declare -F rrg_in_surface >/dev/null 2>&1 && rrg_in_surface "settings.json.template"; then
      local tmpl_sha
      tmpl_sha=$(rrg_blob_sha_of_file "$tmpl" 2>/dev/null)
      if ! rrg_is_covered "$nl" "$ref" "adapters/claude-code/settings.json.template" "$tmpl_sha"; then
        tmpl_gated=0
        N_REVIEW_SKIPPED=$((N_REVIEW_SKIPPED + 1))
        _log "REVIEW-GATE SKIP: settings.json.template merge skipped (stale-not-blocked) -- no PASS harness-change-review record covers blob_sha ${tmpl_sha:-<unresolved>}"
        echo "[auto-install] REVIEW-GATE WARN: settings.json.template changed but has NO PASS harness-change-review record -- SKIPPING the settings merge entirely (stale-not-blocked; run install.sh for the hard-block/authoritative path). See doctrine/review-before-deploy.md." >&2
      fi
    fi
    if [ "$tmpl_gated" -eq 1 ]; then
      merge_settings "$tmpl" "$LIVE_DIR/settings.json" "$nl"
    fi
  fi
  rm -f "$tmpl" 2>/dev/null || true

  # Summary (always, on a real run). N_SELF_SYNC_SKIPPED is ALWAYS present in
  # this line (not gated behind an if-nonzero, unlike the log-file summary
  # below) -- that is the "louder than install.sh" decision: a routine,
  # unmissable, every-run signal at the cost of one number, rather than a
  # per-file block. See the self-sync-guard source block near the top of
  # this file for the full skip-vs-louder reasoning.
  echo "[auto-install] $N_INSTALLED installed, $N_UPDATED updated, $N_UNCHANGED unchanged, $N_SETTINGS_ADDED settings-entries added, $N_DRIFT preserved-as-drift, $N_REVIEW_SKIPPED review-gate-skipped, $N_SELF_SYNC_SKIPPED self-sync-skipped (NL: $nl ref: $ref)" >&2
  if [ "$N_INSTALLED" -gt 0 ] || [ "$N_UPDATED" -gt 0 ] || [ "$N_SETTINGS_ADDED" -gt 0 ] || [ "$N_REVIEW_SKIPPED" -gt 0 ] || [ "$N_SELF_SYNC_SKIPPED" -gt 0 ]; then
    _log "summary: $N_INSTALLED installed, $N_UPDATED updated, $N_UNCHANGED unchanged, $N_SETTINGS_ADDED settings-added, $N_DRIFT drift, $N_REVIEW_SKIPPED review-gate-skipped, $N_SELF_SYNC_SKIPPED self-sync-skipped (ref $ref)"
  fi
  return 0
}

# ============================================================
# Self-test
# ============================================================

run_self_test() {
  local tmp pass=0 fail=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t autoinstall) || { echo "cannot mktemp" >&2; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  export AUTO_INSTALL_NO_FETCH=1
  # Pin a deterministic backup-dir timestamp for assertions.
  export AUTO_INSTALL_TS_OVERRIDE="selftest"

  # ---- Build a canonical NL repo fixture ----
  local CANON="$tmp/nl"
  mkdir -p "$CANON/adapters/claude-code/hooks" "$CANON/adapters/claude-code/scripts" "$CANON/adapters/claude-code/agents"
  printf '%s\n' '# NEURAL-LACE-INSTALLER' 'echo installer' > "$CANON/adapters/claude-code/install.sh"
  printf '%s\n' '#!/bin/bash' 'echo hook-alpha v1' > "$CANON/adapters/claude-code/hooks/alpha.sh"
  printf '%s\n' '#!/bin/bash' 'echo hook-beta v1' > "$CANON/adapters/claude-code/hooks/beta.sh"
  printf '%s\n' '#!/bin/bash' 'echo script-gamma v1' > "$CANON/adapters/claude-code/scripts/gamma.sh"
  # A content surface (.md) — exercises the agents/rules/templates/skills sync path.
  printf '%s\n' '# agent-delta' 'content v1' > "$CANON/adapters/claude-code/agents/delta.md"
  # A directory-form skill (skills/<name>/SKILL.md) — the ONLY Skill-tool-
  # registrable form; exercises the recursive/nested sync path.
  mkdir -p "$CANON/adapters/claude-code/skills/epsilon"
  printf '%s\n' '---' 'name: epsilon' '---' 'skill v1' > "$CANON/adapters/claude-code/skills/epsilon/SKILL.md"
  # A canonical settings.json.template with two SessionStart entries, one of which
  # is the auto-install self-wire entry, plus one Stop entry.
  cat > "$CANON/adapters/claude-code/settings.json.template" <<'TMPL'
{
  "hooks": {
    "SessionStart": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/session-start-auto-install.sh" } ] },
      { "matcher": "", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/canonical-extra.sh" } ] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/canonical-stop.sh" } ] }
    ]
  }
}
TMPL
  ( cd "$CANON" && git init --quiet && git config core.hooksPath "" && git config user.email t@example.com && git config user.name T \
      && git add -A && git commit --quiet -m init && git branch -M master ) || { echo "fixture git init failed" >&2; return 1; }

  # Helper: run main() in a subshell with a fresh LIVE dir + given overrides.
  # Usage: _run_main <live_dir>
  #
  # PORTABILITY TRAP (fixed here, 2026-07-29): re-exec via `"$BASH"`, NEVER a
  # bare `bash`. `$BASH` is the ABSOLUTE PATH of the interpreter currently
  # running this script (a bash builtin, set correctly on 3.2.57 and 5.x
  # alike); a bare `bash` instead resolves via PATH, which on a machine with
  # Homebrew bash ahead of /bin (this Mac's own portability fix) is ALWAYS
  # 5.3.15 regardless of which interpreter `--self-test` itself was invoked
  # under. PROVEN: `/bin/bash -c 'echo $BASH; echo $(bash -c "echo \$BASH")'`
  # prints `/bin/bash` then `/opt/homebrew/bin/bash` -- a bare inner re-exec
  # silently drops the outer interpreter choice. Before this fix, running
  # `/bin/bash session-start-auto-install.sh --self-test` exercised
  # run_self_test()'s OWN code under 3.2.57 but every re-exec'd main() call
  # (i.e. the actual sync/guard logic every scenario asserts on) under
  # whatever `bash` was first on PATH -- a false "tested on bash 3.2.57"
  # claim of exactly the shape that made scope-enforcement-gate.sh report
  # 35/0 on an interpreter it never ran a single command under.
  _run_main() {
    local live="$1"
    ( export NL_CHECKOUT_OVERRIDE="$CANON" LIVE_DIR_OVERRIDE="$live" AUTO_INSTALL_NO_FETCH=1 \
             AUTO_INSTALL_TS_OVERRIDE="selftest" SSF_DISABLE=1
      # Re-derive globals that main() reads from env-driven LIVE_DIR.
      # SSF_DISABLE=1 bypasses the single-flight debounce so every scenario
      # runs main() fully (the debounce has its own lib self-test).
      "$BASH" "$SELF_PATH" 2>&1 )
  }

  local out

  # ---- Scenario 1: fresh-live-installs-all ----
  local L1="$tmp/live1"; mkdir -p "$L1"
  out=$(_run_main "$L1")
  if [ -f "$L1/hooks/alpha.sh" ] && [ -f "$L1/hooks/beta.sh" ] && [ -f "$L1/scripts/gamma.sh" ] \
     && [ -f "$L1/agents/delta.md" ] \
     && diff -q "$L1/hooks/alpha.sh" <(git -C "$CANON" show master:adapters/claude-code/hooks/alpha.sh) >/dev/null 2>&1; then
    echo "PASS: fresh-live-installs-all (incl .md content surface)"; pass=$((pass+1))
  else echo "FAIL: fresh-live-installs-all (out: $out)"; fail=$((fail+1)); fi

  # ---- Scenario 2: up-to-date-noop ----
  out=$(_run_main "$L1")
  if echo "$out" | grep -q "0 installed, 0 updated"; then
    echo "PASS: up-to-date-noop"; pass=$((pass+1))
  else echo "FAIL: up-to-date-noop (out: $out)"; fail=$((fail+1)); fi

  # ---- Scenario 3: stale-live-installs-missing ----
  local L3="$tmp/live3"; mkdir -p "$L3/hooks"
  cp "$CANON/adapters/claude-code/hooks/alpha.sh" "$L3/hooks/alpha.sh"
  out=$(_run_main "$L3")
  # alpha pre-existed (identical) -> unchanged; beta + gamma install.
  if [ -f "$L3/hooks/beta.sh" ] && echo "$out" | grep -qE "1 unchanged"; then
    echo "PASS: stale-live-installs-missing"; pass=$((pass+1))
  else echo "FAIL: stale-live-installs-missing (out: $out)"; fail=$((fail+1)); fi

  # ---- Scenario 4: modified-canonical-hook-master-wins-with-backup ----
  local L4="$tmp/live4"; mkdir -p "$L4/hooks"
  printf '%s\n' '#!/bin/bash' 'echo LOCAL EDIT' > "$L4/hooks/alpha.sh"
  out=$(_run_main "$L4")
  if diff -q "$L4/hooks/alpha.sh" <(git -C "$CANON" show master:adapters/claude-code/hooks/alpha.sh) >/dev/null 2>&1 \
     && ls "$L4"/.backup-auto-install-*/hooks/alpha.sh >/dev/null 2>&1; then
    echo "PASS: modified-canonical-hook-master-wins-with-backup"; pass=$((pass+1))
  else echo "FAIL: modified-canonical-hook-master-wins-with-backup (out: $out)"; fail=$((fail+1)); fi

  # ---- Scenario 5: drift-file-preserved ----
  local L5="$tmp/live5"; mkdir -p "$L5/hooks"
  printf '%s\n' '#!/bin/bash' 'echo local only' > "$L5/hooks/local-only.sh"
  out=$(_run_main "$L5")
  if [ -f "$L5/hooks/local-only.sh" ] && echo "$out" | grep -qE "[1-9][0-9]* preserved-as-drift"; then
    echo "PASS: drift-file-preserved"; pass=$((pass+1))
  else echo "FAIL: drift-file-preserved (out: $out)"; fail=$((fail+1)); fi

  # ---- Scenario 6: feature-branch-reads-master ----
  # Put DIFFERENT content for alpha.sh on a feature branch; master must still win.
  ( cd "$CANON" && git checkout --quiet -b feature-x \
      && printf '%s\n' '#!/bin/bash' 'echo FEATURE BRANCH CONTENT' > adapters/claude-code/hooks/alpha.sh \
      && git commit --quiet -am "feature edit" )
  local L6="$tmp/live6"; mkdir -p "$L6"
  out=$(_run_main "$L6")
  if grep -q "hook-alpha v1" "$L6/hooks/alpha.sh" 2>/dev/null && ! grep -q "FEATURE BRANCH" "$L6/hooks/alpha.sh" 2>/dev/null; then
    echo "PASS: feature-branch-reads-master"; pass=$((pass+1))
  else echo "FAIL: feature-branch-reads-master (got: $(cat "$L6/hooks/alpha.sh" 2>/dev/null))"; fail=$((fail+1)); fi
  ( cd "$CANON" && git checkout --quiet master && git branch -D feature-x >/dev/null 2>&1 )

  # ---- Scenario 7: no-nl-checkout-warns-skips ----
  local L7="$tmp/live7"; mkdir -p "$L7"
  mkdir -p "$tmp/not-nl" "$tmp/empty-home"
  out=$( export LIVE_DIR_OVERRIDE="$L7" NL_CHECKOUT_OVERRIDE="$tmp/not-nl" AUTO_INSTALL_NO_FETCH=1 HOME="$tmp/empty-home"
         # cwd OUTSIDE any NL checkout so the cwd-walk-up fallback finds nothing.
         cd "$tmp/empty-home" || exit 0
         "$BASH" "$SELF_PATH" 2>&1 )
  if echo "$out" | grep -q "no NL checkout found" && [ ! -d "$L7/hooks" ]; then
    echo "PASS: no-nl-checkout-warns-skips"; pass=$((pass+1))
  else echo "FAIL: no-nl-checkout-warns-skips (out: $out)"; fail=$((fail+1)); fi

  # ---- Scenario 8: scripts-synced-too ----
  local L8="$tmp/live8"; mkdir -p "$L8"
  out=$(_run_main "$L8")
  if [ -f "$L8/scripts/gamma.sh" ]; then
    echo "PASS: scripts-synced-too"; pass=$((pass+1))
  else echo "FAIL: scripts-synced-too (out: $out)"; fail=$((fail+1)); fi

  # ---- Scenario 9: settings-self-wire-prepends ----
  local L9="$tmp/live9"; mkdir -p "$L9"
  cat > "$L9/settings.json" <<'LIVE'
{ "hooks": { "SessionStart": [ { "matcher": "", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/preexisting.sh" } ] } ] } }
LIVE
  out=$(_run_main "$L9")
  local first_cmd
  first_cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$L9/settings.json" 2>/dev/null)
  if echo "$first_cmd" | grep -q "session-start-auto-install.sh"; then
    echo "PASS: settings-self-wire-prepends"; pass=$((pass+1))
  else echo "FAIL: settings-self-wire-prepends (first cmd: $first_cmd)"; fail=$((fail+1)); fi

  # ---- Scenario 10: settings-additive-preserves-drift ----
  if jq -e '.hooks.SessionStart[] | select(.hooks[].command | contains("preexisting.sh"))' "$L9/settings.json" >/dev/null 2>&1 \
     && jq -e '.hooks.SessionStart[] | select(.hooks[].command | contains("canonical-extra.sh"))' "$L9/settings.json" >/dev/null 2>&1 \
     && jq -e '.hooks.Stop[] | select(.hooks[].command | contains("canonical-stop.sh"))' "$L9/settings.json" >/dev/null 2>&1; then
    echo "PASS: settings-additive-preserves-drift"; pass=$((pass+1))
  else echo "FAIL: settings-additive-preserves-drift ($(jq -c '.hooks' "$L9/settings.json" 2>/dev/null))"; fail=$((fail+1)); fi

  # ---- Scenario 11: settings-malformed-untouched ----
  local L11="$tmp/live11"; mkdir -p "$L11"
  printf '%s' 'this is { not valid json' > "$L11/settings.json"
  local before11; before11=$(cat "$L11/settings.json")
  out=$(_run_main "$L11")
  if [ "$(cat "$L11/settings.json")" = "$before11" ] && [ -f "$L11/hooks/alpha.sh" ]; then
    echo "PASS: settings-malformed-untouched"; pass=$((pass+1))
  else echo "FAIL: settings-malformed-untouched (now: $(cat "$L11/settings.json"))"; fail=$((fail+1)); fi

  # ---- Scenario 12: settings-merge-idempotent ----
  local before12; before12=$(jq -S . "$L9/settings.json" 2>/dev/null)
  out=$(_run_main "$L9")
  local after12; after12=$(jq -S . "$L9/settings.json" 2>/dev/null)
  if [ "$before12" = "$after12" ] && echo "$out" | grep -q "0 settings-entries added"; then
    echo "PASS: settings-merge-idempotent"; pass=$((pass+1))
  else echo "FAIL: settings-merge-idempotent (changed or non-zero add; out: $out)"; fail=$((fail+1)); fi

  # ---- Scenario 13: crlf-identical-not-updated ----
  # A live hook identical to canonical except CRLF line endings must NOT be
  # re-installed (avoids the install.sh<->auto-install line-ending ping-pong).
  local L13="$tmp/live13"; mkdir -p "$L13/hooks"
  # Inject CRLF reliably via awk (sed '\r' is non-portable on Git Bash).
  git -C "$CANON" show master:adapters/claude-code/hooks/alpha.sh \
    | awk 'BEGIN{ORS="\r\n"} {print}' > "$L13/hooks/alpha.sh"
  local crlf_before; crlf_before=$(md5sum < "$L13/hooks/alpha.sh" 2>/dev/null)
  out=$(_run_main "$L13")
  local crlf_after; crlf_after=$(md5sum < "$L13/hooks/alpha.sh" 2>/dev/null)
  # Correct: 0 updated AND the CRLF file left byte-identical (not normalized).
  if echo "$out" | grep -qE "0 updated" && [ "$crlf_before" = "$crlf_after" ]; then
    echo "PASS: crlf-identical-not-updated"; pass=$((pass+1))
  else echo "FAIL: crlf-identical-not-updated (out: $out; before=$crlf_before after=$crlf_after)"; fail=$((fail+1)); fi

  # ---- Scenario 14: dir-form-skill-installs ----
  # skills/<name>/SKILL.md (the only Skill-tool-registrable form) must be
  # synced into live, nested path intact.
  local L14="$tmp/live14"; mkdir -p "$L14"
  out=$(_run_main "$L14")
  if [ -f "$L14/skills/epsilon/SKILL.md" ] \
     && diff -q "$L14/skills/epsilon/SKILL.md" <(git -C "$CANON" show master:adapters/claude-code/skills/epsilon/SKILL.md) >/dev/null 2>&1; then
    echo "PASS: dir-form-skill-installs"; pass=$((pass+1))
  else echo "FAIL: dir-form-skill-installs (out: $out)"; fail=$((fail+1)); fi

  # ---- Scenario 15: stale-flat-skill-pruned-with-backup ----
  # A live flat skills/<name>.md whose canonical twin is now directory-form
  # must be backed up + removed; a flat skill with NO canonical twin in
  # either form must be preserved as drift.
  local L15="$tmp/live15"; mkdir -p "$L15/skills"
  printf '%s\n' 'old flat epsilon' > "$L15/skills/epsilon.md"
  printf '%s\n' 'operator-local skill' > "$L15/skills/zeta.md"
  out=$(_run_main "$L15")
  if [ ! -e "$L15/skills/epsilon.md" ] \
     && ls "$L15"/.backup-auto-install-*/skills/epsilon.md >/dev/null 2>&1 \
     && [ -f "$L15/skills/zeta.md" ] \
     && [ -f "$L15/skills/epsilon/SKILL.md" ]; then
    echo "PASS: stale-flat-skill-pruned-with-backup"; pass=$((pass+1))
  else echo "FAIL: stale-flat-skill-pruned-with-backup (out: $out; ls: $(ls -R "$L15/skills" 2>/dev/null))"; fail=$((fail+1)); fi

  # ---- Scenario 16/17: review-before-deploy gate (Amendment F: fail-open
  # skip+warn, never a hard block) -- a SEPARATE fixture repo (CANON2) with
  # its own bootstrapped docs/reviews/records/, so scenarios 1-15 above (run
  # against the bootstrap-less CANON) are entirely unaffected. ----
  local CANON2="$tmp/nl2"
  mkdir -p "$CANON2/adapters/claude-code/hooks" "$CANON2/adapters/claude-code/scripts"
  printf '%s\n' '# NEURAL-LACE-INSTALLER' 'echo installer' > "$CANON2/adapters/claude-code/install.sh"
  printf '#!/bin/bash\necho covered-v1\n' > "$CANON2/adapters/claude-code/hooks/covered.sh"
  printf '#!/bin/bash\necho uncovered-v1\n' > "$CANON2/adapters/claude-code/hooks/uncovered.sh"
  mkdir -p "$CANON2/docs/reviews/records"
  ( cd "$CANON2" && git init --quiet && git config core.hooksPath "" && git config user.email t@example.com && git config user.name T )
  # Two-commit cutover pattern (harness-reviewer C2-A -- see
  # lib/review-record-gate-lib.sh's rrg_is_covered grandfather arm and its own
  # self-test around "cutover_ref-less grandfather manifest is not honored").
  # The grandfather arm verifies each row against the manifest's OWN
  # cutover_ref by re-reading that ref's tree, so a row cannot cite a commit
  # that does not exist yet -- the content commit must land FIRST and the
  # manifest that cites it SECOND. This fixture previously wrote a
  # grandfather-manifest.json with NO cutover_ref at all, which
  # rrg_is_covered's own self-test pins as honoring NOTHING: covered.sh could
  # never verify, so a "fresh install" run treated the genuinely-grandfathered
  # covered.sh the same as the genuinely-unreviewed uncovered.sh (self-test
  # PROVEN: both were skipped, "covered exists: n" in the failure output).
  ( cd "$CANON2" && git add -A && git commit --quiet -m "pre-cutover: v1 content" )
  local CUTOVER_SHA; CUTOVER_SHA=$(cd "$CANON2" && git rev-parse HEAD)
  local covered_v1_sha uncovered_v1_sha
  covered_v1_sha=$(git -C "$CANON2" rev-parse "HEAD:adapters/claude-code/hooks/covered.sh")
  uncovered_v1_sha=$(git -C "$CANON2" rev-parse "HEAD:adapters/claude-code/hooks/uncovered.sh")
  cat > "$CANON2/docs/reviews/records/grandfather-manifest.json" <<EOF
{"cutover_ref":"$CUTOVER_SHA","entries":[
  {"path":"adapters/claude-code/hooks/covered.sh","blob_sha":"$covered_v1_sha"},
  {"path":"adapters/claude-code/hooks/uncovered.sh","blob_sha":"$uncovered_v1_sha"}
]}
EOF
  printf '{"entries":[]}\n' > "$CANON2/docs/reviews/records/index.json"
  ( cd "$CANON2" && git add -A && git commit --quiet -m "bootstrap grandfather at cutover" && git branch -M master )

  # ---- Scenario 16: fresh install -- covered file installs, unreviewed file is skipped+warned ----
  # First bump uncovered.sh to v2 with NO new review record (simulating an
  # unreviewed change landing on master), leaving covered.sh untouched.
  printf '#!/bin/bash\necho uncovered-v2-UNREVIEWED\n' > "$CANON2/adapters/claude-code/hooks/uncovered.sh"
  ( cd "$CANON2" && git commit --quiet -am "v2 uncovered.sh (unreviewed)" )
  local L16="$tmp/live16"; mkdir -p "$L16"
  out=$( export NL_CHECKOUT_OVERRIDE="$CANON2" LIVE_DIR_OVERRIDE="$L16" AUTO_INSTALL_NO_FETCH=1 \
           AUTO_INSTALL_TS_OVERRIDE="selftest" SSF_DISABLE=1
         "$BASH" "$SELF_PATH" 2>&1 )
  if [ -f "$L16/hooks/covered.sh" ] && [ ! -e "$L16/hooks/uncovered.sh" ] \
     && echo "$out" | grep -q "REVIEW-GATE WARN: hooks/uncovered.sh" \
     && echo "$out" | grep -qE "[1-9][0-9]* review-gate-skipped"; then
    echo "PASS: review-gate-skips-uncovered-fresh-install"; pass=$((pass+1))
  else
    echo "FAIL: review-gate-skips-uncovered-fresh-install (out: $out; covered exists: $([ -f "$L16/hooks/covered.sh" ] && echo y || echo n); uncovered exists: $([ -e "$L16/hooks/uncovered.sh" ] && echo y || echo n))"
    fail=$((fail+1))
  fi

  # ---- Scenario 17: stale-not-blocked -- a previously-installed (reviewed
  # v1) copy is LEFT IN PLACE when master's content becomes uncovered,
  # rather than being wiped or force-updated. ----
  local L17="$tmp/live17"; mkdir -p "$L17/hooks"
  printf '#!/bin/bash\necho uncovered-v1\n' > "$L17/hooks/uncovered.sh"
  out=$( export NL_CHECKOUT_OVERRIDE="$CANON2" LIVE_DIR_OVERRIDE="$L17" AUTO_INSTALL_NO_FETCH=1 \
           AUTO_INSTALL_TS_OVERRIDE="selftest" SSF_DISABLE=1
         "$BASH" "$SELF_PATH" 2>&1 )
  if grep -q "uncovered-v1" "$L17/hooks/uncovered.sh" 2>/dev/null \
     && ! grep -q "UNREVIEWED" "$L17/hooks/uncovered.sh" 2>/dev/null \
     && echo "$out" | grep -q "REVIEW-GATE WARN: hooks/uncovered.sh"; then
    echo "PASS: review-gate-leaves-stale-reviewed-copy-in-place"; pass=$((pass+1))
  else
    echo "FAIL: review-gate-leaves-stale-reviewed-copy-in-place (out: $out; live content: $(cat "$L17/hooks/uncovered.sh" 2>/dev/null))"
    fail=$((fail+1))
  fi

  # ---- Scenario 18: settings.json.template itself is gated (harness-review
  # REFORMULATE fixup, finding 1b) -- an uncovered template change skips the
  # WHOLE merge_settings call (0 settings-entries added), warns loudly, and
  # counts toward review-gate-skipped; live settings.json is left untouched. ----
  local CANON3="$tmp/nl3"
  mkdir -p "$CANON3/adapters/claude-code/hooks"
  printf '%s\n' '# NEURAL-LACE-INSTALLER' 'echo installer' > "$CANON3/adapters/claude-code/install.sh"
  cat > "$CANON3/adapters/claude-code/settings.json.template" <<'TMPL'
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/session-start-auto-install.sh"}]}]}}
TMPL
  mkdir -p "$CANON3/docs/reviews/records"
  ( cd "$CANON3" && git init --quiet && git config core.hooksPath "" && git config user.email t@example.com && git config user.name T )
  local tmpl_v1_sha
  tmpl_v1_sha=$(git -C "$CANON3" hash-object "$CANON3/adapters/claude-code/settings.json.template")
  cat > "$CANON3/docs/reviews/records/grandfather-manifest.json" <<EOF
{"entries":[{"path":"adapters/claude-code/settings.json.template","blob_sha":"$tmpl_v1_sha"}]}
EOF
  printf '{"entries":[]}\n' > "$CANON3/docs/reviews/records/index.json"
  ( cd "$CANON3" && git add -A && git commit --quiet -m "v1 (grandfathered)" && git branch -M master )

  # Bump the template with a NEW unreviewed hook-wiring, no new review record.
  cat > "$CANON3/adapters/claude-code/settings.json.template" <<'TMPL'
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/session-start-auto-install.sh"}]},{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/unreviewed-new-hook.sh"}]}]}}
TMPL
  ( cd "$CANON3" && git commit --quiet -am "v2 settings.json.template (unreviewed new wiring)" )

  local L18="$tmp/live18"; mkdir -p "$L18"
  out=$( export NL_CHECKOUT_OVERRIDE="$CANON3" LIVE_DIR_OVERRIDE="$L18" AUTO_INSTALL_NO_FETCH=1 \
           AUTO_INSTALL_TS_OVERRIDE="selftest" SSF_DISABLE=1
         "$BASH" "$SELF_PATH" 2>&1 )
  if echo "$out" | grep -q "REVIEW-GATE WARN: settings.json.template" \
     && echo "$out" | grep -q "0 settings-entries added" \
     && echo "$out" | grep -qE "[1-9][0-9]* review-gate-skipped" \
     && { [ ! -f "$L18/settings.json" ] || ! grep -q "unreviewed-new-hook" "$L18/settings.json" 2>/dev/null; }; then
    echo "PASS: review-gate-skips-uncovered-settings-template"; pass=$((pass+1))
  else
    echo "FAIL: review-gate-skips-uncovered-settings-template (out: $out; settings: $(cat "$L18/settings.json" 2>/dev/null))"
    fail=$((fail+1))
  fi

  # ============================================================
  # SELF-SYNC-01 scenarios (19-22). Scenarios 1-18 above NEVER call `ln` --
  # confirmed by `grep -n 'ln -s' hooks/session-start-auto-install.sh`
  # matching only inside these new scenarios -- so they are, unmodified,
  # the "behaviour is unchanged when paths differ / copy-based install"
  # half of this guard's contract (the Windows/Git-Bash acceptance bar).
  # Scenarios 19-21 below are the "SKIP on a genuine self-sync" half.
  # ============================================================

  # ---- Scenario 19 (GOLDEN SCENARIO): today's incident, replayed. A live
  # hooks/ symlinked back onto the repo's OWN adapters/claude-code/hooks
  # (the actual topology on this Mac's symlink-based install), with the
  # repo's working tree carrying content NEWER than what is committed on
  # the ref this hook reads (`master` here -- the fixture has no origin
  # remote, same as real machines before the first fetch). This is exactly
  # the shape that reverted hooks/model-pin-gate.sh (265 lines -> its
  # pre-change state) and 26 siblings on 2026-07-29. The newer content must
  # SURVIVE, not be overwritten with the older committed content. ----
  local L19="$tmp/live19"; mkdir -p "$L19"
  ln -s "$CANON/adapters/claude-code/hooks" "$L19/hooks"
  local alpha_path="$CANON/adapters/claude-code/hooks/alpha.sh"
  local alpha_committed; alpha_committed=$(cat "$alpha_path")
  printf '%s\n' '#!/bin/bash' 'echo NEWER UNCOMMITTED WORK -- must survive the sync' > "$alpha_path"
  out=$(_run_main "$L19")
  if grep -q "NEWER UNCOMMITTED WORK" "$alpha_path" 2>/dev/null \
     && echo "$out" | grep -qE "[1-9][0-9]* self-sync-skipped"; then
    echo "PASS: SELF-SYNC-01-golden-scenario (symlinked hooks/, newer repo content survives the sync)"; pass=$((pass+1))
  else
    echo "FAIL: SELF-SYNC-01-golden-scenario (out: $out; alpha content now: $(cat "$alpha_path" 2>/dev/null))"
    fail=$((fail+1))
  fi
  printf '%s\n' "$alpha_committed" > "$alpha_path"  # restore committed content for hygiene

  # ---- Scenario 20: settings-merge path carries the same guard.
  #
  # TOPOLOGY NOTE (load-bearing, found while writing this test): symlinking
  # ONLY the settings.json LEAF (`ln -s repo/settings.json live/settings.json`)
  # does NOT reproduce the hazard -- `mv work live/settings.json` on a
  # symlink DESTINATION replaces the symlink itself (rename(2) semantics),
  # never writing through it. PROVEN by direct experiment: `mv` onto a
  # symlink-to-a-file leaves the symlink's target byte-for-byte untouched
  # and turns the destination into a plain file. The real hazard requires
  # the PARENT directory to be the symlink and "settings.json" to be an
  # ordinary leaf name reached through it -- confirmed by the same
  # experiment: `mv` through a symlinked PARENT lands squarely on the real
  # file. So this scenario symlinks the whole live dir (mirroring "this
  # Mac's ~/.claude IS a symlink" rather than "one file is"), which also
  # exercises the file-sync guard for hooks/scripts/etc under the same
  # symlink -- that's fine, this scenario asserts on settings.json only;
  # S19 already isolates the file-sync guard on its own.
  local L20="$tmp/live20"
  rm -rf "$L20"
  ln -s "$CANON/adapters/claude-code" "$L20"
  printf '%s\n' '{ "hooks": { "SessionStart": [ { "matcher": "", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/preexisting.sh" } ] } ] } }' > "$CANON/adapters/claude-code/settings.json"
  local before20; before20=$(cat "$CANON/adapters/claude-code/settings.json")
  out=$(_run_main "$L20")
  local after20; after20=$(cat "$CANON/adapters/claude-code/settings.json" 2>/dev/null)
  if [ "$before20" = "$after20" ] \
     && ! echo "$after20" | grep -q "canonical-extra.sh" \
     && echo "$out" | grep -q "0 settings-entries added" \
     && echo "$out" | grep -qE "[1-9][0-9]* self-sync-skipped"; then
    echo "PASS: SELF-SYNC-01-settings-merge-guard (whole live dir symlinked into repo -- merge skipped, content untouched)"; pass=$((pass+1))
  else
    echo "FAIL: SELF-SYNC-01-settings-merge-guard (out: $out; settings now: $after20)"
    fail=$((fail+1))
  fi
  rm -f "$CANON/adapters/claude-code/settings.json"  # cleanup

  # ---- Scenario 21: prune-path (delete) self-sync guard. A stale flat
  # skill living directly INSIDE the repo's own skills/ dir, reached
  # through a symlinked live skills/, must NOT be deleted by the
  # migrate-to-directory-form prune -- that rm -f would delete a repo file,
  # not a stale live copy. ----
  local L21="$tmp/live21"; mkdir -p "$L21"
  ln -s "$CANON/adapters/claude-code/skills" "$L21/skills"
  printf '%s\n' 'old flat epsilon living in the repo' > "$CANON/adapters/claude-code/skills/epsilon.md"
  out=$(_run_main "$L21")
  local log21; log21=$(cat "$L21/state/auto-install-log-selftest.txt" 2>/dev/null)
  if [ -f "$CANON/adapters/claude-code/skills/epsilon.md" ] \
     && grep -q "old flat epsilon living in the repo" "$CANON/adapters/claude-code/skills/epsilon.md" \
     && echo "$log21" | grep -q "prune of skills/epsilon.md skipped"; then
    echo "PASS: SELF-SYNC-01-prune-guard (symlinked skills/, repo's own stale-flat file survives the migration prune)"; pass=$((pass+1))
  else
    echo "FAIL: SELF-SYNC-01-prune-guard (out: $out; repo epsilon.md: $(cat "$CANON/adapters/claude-code/skills/epsilon.md" 2>/dev/null); log: $log21)"
    fail=$((fail+1))
  fi
  rm -f "$CANON/adapters/claude-code/skills/epsilon.md"  # cleanup

  # ---- Scenario 22: guard is SILENT on an ordinary copy-mode install (no
  # symlinks anywhere) -- the "must not over-fire" half of the contract.
  # Re-runs the already-installed L1 (idempotent no-op, like Scenario 2). ----
  out=$(_run_main "$L1")
  if echo "$out" | grep -qE "0 self-sync-skipped"; then
    echo "PASS: SELF-SYNC-01-silent-on-copy-mode (no symlinks anywhere -> 0 self-sync-skipped)"; pass=$((pass+1))
  else
    echo "FAIL: SELF-SYNC-01-silent-on-copy-mode (out: $out)"; fail=$((fail+1))
  fi

  # ============================================================
  # Kill-switch scenarios (23-24, 2026-07-29 second incident: this hook
  # overwrote committed branch work TWICE in one day via the same
  # self-sync defect; between the two there was no way to turn it off).
  # ============================================================

  # ---- Scenario 23: marker present -> ZERO files touched, main() returns
  # before doing any work. Asserted on the FILESYSTEM (no hooks/scripts/state
  # dir ever created), not on the log line alone -- a log-only assertion is
  # exactly the false-green class this session has already shipped three
  # times elsewhere. The log line is also checked, but as a SECONDARY signal. ----
  local L23="$tmp/live23"
  mkdir -p "$L23/local"
  : > "$L23/local/no-auto-install"
  local rc23
  ( export NL_CHECKOUT_OVERRIDE="$CANON" LIVE_DIR_OVERRIDE="$L23" AUTO_INSTALL_NO_FETCH=1 \
           AUTO_INSTALL_TS_OVERRIDE="selftest" SSF_DISABLE=1
    "$BASH" "$SELF_PATH" > "$tmp/s23.out" 2>&1 )
  rc23=$?
  out=$(cat "$tmp/s23.out" 2>/dev/null)
  if [ "$rc23" -eq 0 ] \
     && [ ! -e "$L23/hooks" ] && [ ! -e "$L23/scripts" ] && [ ! -e "$L23/agents" ] \
     && [ ! -e "$L23/state" ] && [ ! -d "$L23"/.backup-auto-install-* ] \
     && echo "$out" | grep -q "KILL-SWITCH" \
     && echo "$out" | grep -qF "$L23/local/no-auto-install"; then
    echo "PASS: kill-switch-marker-present-zero-files-touched (exit 0, no hooks/scripts/state/backup dir ever created)"; pass=$((pass+1))
  else
    echo "FAIL: kill-switch-marker-present-zero-files-touched (rc=$rc23; out: $out; live tree: $(find "$L23" 2>/dev/null | tr '\n' ' '))"
    fail=$((fail+1))
  fi

  # ---- Scenario 24: marker ABSENT -> normal behavior, unchanged (the
  # explicit off-means-on pairing for Scenario 23; a fresh live dir with no
  # marker installs normally, same as Scenario 1). ----
  local L24="$tmp/live24"; mkdir -p "$L24"
  out=$(_run_main "$L24")
  if [ -f "$L24/hooks/alpha.sh" ] && [ -f "$L24/scripts/gamma.sh" ] && ! echo "$out" | grep -q "KILL-SWITCH"; then
    echo "PASS: kill-switch-marker-absent-normal-behavior-unchanged"; pass=$((pass+1))
  else
    echo "FAIL: kill-switch-marker-absent-normal-behavior-unchanged (out: $out)"; fail=$((fail+1))
  fi

  # ---- Scenario 25 (T17 remedy R1, 2026-08-04): config/ syncs EVERY
  # extension in its set (.json AND .txt), not just one -- the exact class
  # of gap that left dispatch-chain-gate.sh's config/model-policy.json and
  # config/g2-grandfather-slugs.txt undeployed on every installed machine
  # before this fix (SYNC_SUBDIRS did not carry config/ at all, and
  # _subdir_ext was a single scalar extension per subdir -- config/ is the
  # first heterogeneous one). ----
  mkdir -p "$CANON/adapters/claude-code/config"
  printf '%s\n' '{"agents":{"plan-phase-builder":{"category":"build"}}}' > "$CANON/adapters/claude-code/config/model-policy.json"
  printf '%s\n' '# g2 grandfather list (opaque sha256 entries)' > "$CANON/adapters/claude-code/config/g2-grandfather-slugs.txt"
  ( cd "$CANON" && git add -A && git commit --quiet -m "add config/ (T17 remedy self-test fixture)" )
  local L25="$tmp/live25"; mkdir -p "$L25"
  out=$(_run_main "$L25")
  if [ -f "$L25/config/model-policy.json" ] && [ -f "$L25/config/g2-grandfather-slugs.txt" ] \
     && diff -q "$L25/config/model-policy.json" <(git -C "$CANON" show master:adapters/claude-code/config/model-policy.json) >/dev/null 2>&1 \
     && diff -q "$L25/config/g2-grandfather-slugs.txt" <(git -C "$CANON" show master:adapters/claude-code/config/g2-grandfather-slugs.txt) >/dev/null 2>&1; then
    echo "PASS: config-subdir-syncs-heterogeneous-extensions (.json AND .txt both deployed)"; pass=$((pass+1))
  else
    echo "FAIL: config-subdir-syncs-heterogeneous-extensions (out: $out; ls: $(ls "$L25/config" 2>/dev/null))"; fail=$((fail+1))
  fi

  echo ""
  echo "[self-test] $pass passed, $fail failed"
  return "$fail"
}

# ============================================================
# Entry point
# ============================================================

# Resolve own path so the self-test can re-exec this script in subshells.
SELF_PATH="${BASH_SOURCE[0]}"
case "$SELF_PATH" in
  /*) : ;;
  *) SELF_PATH="$(cd "$(dirname "$SELF_PATH")" && pwd)/$(basename "$SELF_PATH")" ;;
esac

case "${1:-}" in
  --self-test)
    run_self_test
    exit $?
    ;;
  *)
    cat >/dev/null 2>&1 || true
    main
    exit 0
    ;;
esac
