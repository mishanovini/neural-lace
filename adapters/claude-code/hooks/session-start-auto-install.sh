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
# Self-test: invoke with --self-test to exercise the scenario matrix (15 cases).

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
# install.sh's rules-prune step is the one place stale rules/*.md get removed.)
SYNC_SUBDIRS="hooks scripts agents rules templates skills doctrine"

# Per-subdir canonical file extension: executable (.sh) vs content (.md).
_subdir_ext() {
  case "$1" in
    hooks|scripts) printf 'sh' ;;
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

# Best-effort bounded fetch of origin/master. Never blocks > timeout. Skippable.
ensure_fresh_origin_master() {
  local nl="$1"
  [ "${AUTO_INSTALL_NO_FETCH:-0}" = "1" ] && return 0
  git -C "$nl" remote 2>/dev/null | grep -q '^origin$' || return 0
  if command -v timeout >/dev/null 2>&1; then
    timeout "$FETCH_TIMEOUT_SECONDS" git -C "$nl" fetch origin master --quiet >/dev/null 2>&1 || true
  else
    git -C "$nl" fetch origin master --quiet >/dev/null 2>&1 || true
  fi
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
# templates|skills=.md) into live. master-wins. Args: nl_dir, ref, subdir
sync_canonical_files() {
  local nl="$1" ref="$2" subdir="$3"
  local live_sub="$LIVE_DIR/$subdir"
  local ext; ext=$(_subdir_ext "$subdir")
  mkdir -p "$live_sub" 2>/dev/null || true

  # Canonical paths for this subdir at the ref (extension per subdir),
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
    | grep "\\.${ext}\$" | sed "s#^adapters/claude-code/$subdir/##" | sort -u)
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
    if [ ! -e "$target" ]; then
      cp "$tmp" "$target" 2>/dev/null && { [ "$ext" = sh ] && chmod +x "$target" 2>/dev/null; :; }
      N_INSTALLED=$((N_INSTALLED + 1))
      _log "installed $subdir/$b (was missing)"
    elif ! _content_same "$tmp" "$target"; then
      # master-wins, but back up the prior live copy first ($b may be nested).
      mkdir -p "$BACKUP_DIR/$subdir/$(dirname "$b")" 2>/dev/null || true
      cp "$target" "$BACKUP_DIR/$subdir/$b" 2>/dev/null || true
      cp "$tmp" "$target" 2>/dev/null && { [ "$ext" = sh ] && chmod +x "$target" 2>/dev/null; :; }
      N_UPDATED=$((N_UPDATED + 1))
      _log "updated $subdir/$b (backed up prior copy to $(basename "$BACKUP_DIR")/$subdir/)"
    else
      N_UNCHANGED=$((N_UNCHANGED + 1))
    fi
    rm -f "$tmp"
  done <<< "$canon_list"

  # Count live files NOT in canonical (informational drift; never touched —
  # with ONE exception below for migrated flat skills).
  local f base
  for f in "$live_sub"/*."$ext"; do
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
        mkdir -p "$BACKUP_DIR/$subdir" 2>/dev/null || true
        cp "$f" "$BACKUP_DIR/$subdir/$base" 2>/dev/null || true
        rm -f "$f" 2>/dev/null || true
        _log "pruned stale flat skills/$base (canonical is now skills/${base%.md}/SKILL.md; backed up)"
        continue
      fi
      N_DRIFT=$((N_DRIFT + 1))
    fi
  done
  return 0
}

# Surgical additive-merge of missing canonical settings.json hook-entries.
# Args: template_json_path, live_settings_path
merge_settings() {
  local template="$1" live="$2"

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
  local nl ref
  nl=$(discover_nl_checkout)
  if [ -z "$nl" ]; then
    echo "[auto-install] no NL checkout found — skipping (set $LIVE_DIR/local/nl-checkout-path.txt to enable)" >&2
    return 0
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
  local tmpl
  tmpl=$(mktemp 2>/dev/null)
  if [ -n "$tmpl" ] && git -C "$nl" show "$ref:adapters/claude-code/settings.json.template" > "$tmpl" 2>/dev/null; then
    merge_settings "$tmpl" "$LIVE_DIR/settings.json"
  fi
  rm -f "$tmpl" 2>/dev/null || true

  # Summary (always, on a real run).
  echo "[auto-install] $N_INSTALLED installed, $N_UPDATED updated, $N_UNCHANGED unchanged, $N_SETTINGS_ADDED settings-entries added, $N_DRIFT preserved-as-drift (NL: $nl ref: $ref)" >&2
  if [ "$N_INSTALLED" -gt 0 ] || [ "$N_UPDATED" -gt 0 ] || [ "$N_SETTINGS_ADDED" -gt 0 ]; then
    _log "summary: $N_INSTALLED installed, $N_UPDATED updated, $N_UNCHANGED unchanged, $N_SETTINGS_ADDED settings-added, $N_DRIFT drift (ref $ref)"
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
  _run_main() {
    local live="$1"
    ( export NL_CHECKOUT_OVERRIDE="$CANON" LIVE_DIR_OVERRIDE="$live" AUTO_INSTALL_NO_FETCH=1 \
             AUTO_INSTALL_TS_OVERRIDE="selftest"
      # Re-derive globals that main() reads from env-driven LIVE_DIR.
      bash "$SELF_PATH" 2>&1 )
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
         bash "$SELF_PATH" 2>&1 )
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
