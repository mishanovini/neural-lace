# E.9 doctor predicate (implemented verbatim by E.10 per §E.0.1)

Owner: E.10 builder only (harness-doctor.sh is E.10-exclusive this wave). This file
names the exact command + RED condition + fixture per §E.0.1 point 3 — E.9 does not
edit harness-doctor.sh.

## Predicate

Both E.9 hooks must be (1) present on disk, (2) wired into
`settings.json.template`'s `PostToolUse` (context-watermark.sh, matcher covering all
tools per spec — an empty/`""` matcher or a matcher pattern that matches every tool
name) and `PreCompact` (pre-compact-continuity.sh, BOTH `auto` and `manual` matcher
entries), and (3) the session-handoff output directory must be writable.

Suggested check function (mirrors `check_wiring_resolves` / `check_manifest`'s
existing style — one function, `CHECKS_RUN` incremented once, `_red`/`_warn` per
the doctor's established helpers):

```bash
check_wave_e_e9_precompaction() {
  local live_home="$1" repo_root="$2"
  local template=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/settings.json.template" ]] \
    && template="${repo_root}/adapters/claude-code/settings.json.template"
  [[ -z "$template" && -f "${live_home}/settings.json" ]] && template="${live_home}/settings.json"

  if [[ -z "$template" ]]; then
    _warn "wave-e-e9-precompaction" "no settings template/live settings resolved — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # (1) both hook files exist on disk (repo hooks/ dir preferred, live fallback).
  local hooks_dir="${repo_root}/adapters/claude-code/hooks"
  [[ -d "$hooks_dir" ]] || hooks_dir="${live_home}/hooks"
  if [[ ! -f "${hooks_dir}/context-watermark.sh" ]]; then
    _red "wave-e-e9-precompaction" "context-watermark.sh missing from ${hooks_dir} — run: bash install.sh (or restore from adapters/claude-code/hooks/)"
  fi
  if [[ ! -f "${hooks_dir}/pre-compact-continuity.sh" ]]; then
    _red "wave-e-e9-precompaction" "pre-compact-continuity.sh missing from ${hooks_dir} — run: bash install.sh (or restore from adapters/claude-code/hooks/)"
  fi

  # (2a) PostToolUse wiring: context-watermark.sh referenced in the template's
  # PostToolUse chain.
  if ! grep -q 'context-watermark\.sh' "$template" 2>/dev/null; then
    _red "wave-e-e9-precompaction" "context-watermark.sh not wired into PostToolUse — add a PostToolUse entry (matcher covering all tools) invoking ~/.claude/hooks/context-watermark.sh"
  fi

  # (2b) PreCompact wiring: pre-compact-continuity.sh referenced, AND both
  # "auto" and "manual" matcher values present in a PreCompact block.
  if ! grep -q 'pre-compact-continuity\.sh' "$template" 2>/dev/null; then
    _red "wave-e-e9-precompaction" "pre-compact-continuity.sh not wired into PreCompact — add PreCompact entries for both auto and manual matchers invoking ~/.claude/hooks/pre-compact-continuity.sh"
  else
    # Extract the PreCompact block's matcher values (assumes node is available,
    # matching the doctor's existing node-based chain-count assertions elsewhere).
    local matchers
    matchers="$(node -e "
      const fs=require('fs');
      let cfg;
      try { cfg = JSON.parse(fs.readFileSync('${template}','utf8')); } catch(e) { process.exit(0); }
      const pc = (cfg.hooks && cfg.hooks.PreCompact) || [];
      console.log(pc.map(b => b.matcher).join(','));
    " 2>/dev/null)"
    if ! printf '%s' "$matchers" | grep -q 'auto' || ! printf '%s' "$matchers" | grep -q 'manual'; then
      _red "wave-e-e9-precompaction" "PreCompact chain missing one of the auto/manual matchers (found: '${matchers}') — pre-compact-continuity.sh must be wired on BOTH"
    fi
  fi

  # (3) session-handoff output directory writable (create-if-absent probe;
  # never touches an existing file, only tests mkdir + a throwaway temp file).
  local handoff_dir="${HOME}/.claude/state/session-handoff"
  if ! mkdir -p "$handoff_dir" 2>/dev/null || ! touch "${handoff_dir}/.doctor-write-probe" 2>/dev/null; then
    _red "wave-e-e9-precompaction" "session-handoff directory not writable: ${handoff_dir} — check permissions"
  else
    rm -f "${handoff_dir}/.doctor-write-probe" 2>/dev/null || true
  fi

  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

## RED conditions (enumerated)

1. `context-watermark.sh` absent from `hooks/`.
2. `pre-compact-continuity.sh` absent from `hooks/`.
3. Neither hook referenced anywhere in `settings.json.template`'s `PostToolUse`
   (for context-watermark.sh) / `PreCompact` (for pre-compact-continuity.sh) chains.
4. `PreCompact` chain wired but missing the `auto` or `manual` matcher (or both).
5. `~/.claude/state/session-handoff/` cannot be created or written to.

## Red fixture (for E.10's self-test of this predicate)

```bash
# Fixture: a template missing the PreCompact "manual" matcher entirely.
tmp="$(mktemp -d)"
cat > "$tmp/settings.json.template" <<'JSON'
{
  "hooks": {
    "PostToolUse": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/context-watermark.sh"}]}
    ],
    "PreCompact": [
      {"matcher": "auto", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/pre-compact-continuity.sh"}]}
    ]
  }
}
JSON
mkdir -p "$tmp/adapters/claude-code/hooks"
touch "$tmp/adapters/claude-code/hooks/context-watermark.sh" "$tmp/adapters/claude-code/hooks/pre-compact-continuity.sh"
# Running check_wave_e_e9_precompaction against $tmp as repo_root must RED on
# finding #4 (manual matcher absent) and pass every other sub-check.
```

## Notes for E.10

- The two hook-existence checks (#1, #2) are defensive belt-and-suspenders — by
  the time E.10 runs, both hooks should already be cherry-picked from this
  branch onto the integration branch. They exist mainly to catch a bad
  cherry-pick / merge, not as the primary signal.
- The template-wiring checks (#3, #4) ARE the primary signal — this hook is
  useless if only half-wired (e.g. PreCompact wired for `auto` but not
  `manual` silently drops the manual-`/compact`-triggered case, exactly the
  class of gap `check_template_live_drift` and friends exist to catch
  elsewhere in this same doctor).
- `schemas/manifest.schema.json`'s `events` enum has no `"PreCompact"` value
  yet (see `manifest-entry.json` fragment's `_fragment_note` in this same
  directory) — E.10 should decide whether to add it in the same pass as
  wiring these predicates, since `manifest-check.sh`'s own coverage
  cross-check may otherwise choke on (or silently accept a wrong value for)
  the `pre-compact-continuity` entry.
