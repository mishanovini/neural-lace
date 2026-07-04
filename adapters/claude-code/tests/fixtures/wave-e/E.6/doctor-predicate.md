# E.6 doctor predicate — NEEDS-YOU ledger

Per `docs/plans/nl-overhaul-program-2026-07-specs-e.md` §E.0.1 rule 3: the E.6
builder does NOT edit `harness-doctor.sh` directly; this fragment is the exact
predicate for the E.10 builder to implement verbatim.

## Predicate 1 — script exists + executable + self-test entrypoint present

```bash
test -f "$REPO_ROOT/adapters/claude-code/scripts/needs-you.sh" && \
test -x "$REPO_ROOT/adapters/claude-code/scripts/needs-you.sh" && \
grep -q -- '--self-test' "$REPO_ROOT/adapters/claude-code/scripts/needs-you.sh"
```

- **RED condition:** file missing, present but not executable, or missing a
  `--self-test` entrypoint (mirrors the `selftest: true` manifest claim —
  a manifest that claims self-test coverage the file doesn't actually have
  is exactly the class of drift `manifest-check.sh` + this predicate exist
  to catch together).
- **GREEN when:** all three true.
- **Fixture for a synthetic RED:** copy the script to a scratch path and
  `chmod -x` it (mirrors E.8's own predicate-1 fixture style):
  ```bash
  cp "$REPO_ROOT/adapters/claude-code/scripts/needs-you.sh" /tmp/ny-red-fixture.sh
  chmod -x /tmp/ny-red-fixture.sh
  test -x /tmp/ny-red-fixture.sh && echo "unexpected GREEN" || echo "RED confirmed"
  ```

## Predicate 2 — freshness: NEEDS-YOU.md exists at main-checkout root AND is
## fresh (≤7d) whenever an Awaiting-decision item is open

This is the spec's own stated predicate (§E.6: "NEEDS-YOU.md exists at
main-checkout root AND mtime ≤7d when any Awaiting-decision item is open").

```bash
check_wave_e_e6_needs_you() {
  local repo_root="$1"
  local main_root=""
  # Resolve the MAIN checkout root the same way needs-you.sh does (via
  # hooks/lib/nl-paths.sh's nl_main_checkout_root, sourced fresh here rather
  # than assuming the doctor process already has it in scope).
  local nlpaths="${repo_root}/adapters/claude-code/hooks/lib/nl-paths.sh"
  if [[ -f "$nlpaths" ]]; then
    # shellcheck disable=SC1090
    main_root=$(bash -c "source '$nlpaths'; nl_main_checkout_root" 2>/dev/null)
  fi
  [[ -n "$main_root" ]] || main_root="$repo_root"

  local ledger_md="${main_root}/NEEDS-YOU.md"
  local ledger_state="${HOME}/.claude/state/needs-you/ledger.json"

  # No ledger state at all yet (needs-you.sh never invoked on this machine) —
  # tolerate-absent, not a RED (mirrors E.8's nl-issues.jsonl "never run yet"
  # tolerance). Nothing to be fresh ABOUT.
  if [[ ! -f "$ledger_state" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local open_decisions
  open_decisions=$(jq '[.items[] | select(.section == "decision" and .state == "open")] | length' "$ledger_state" 2>/dev/null || echo 0)

  if [[ "$open_decisions" -gt 0 ]]; then
    if [[ ! -f "$ledger_md" ]]; then
      _red "wave-e-e6-needs-you" "NEEDS-YOU.md missing at main-checkout root ($ledger_md) despite $open_decisions open Awaiting-decision item(s) — run: bash adapters/claude-code/scripts/needs-you.sh render"
    else
      local age_secs now mtime
      now=$(date -u +%s)
      mtime=$(stat -c %Y "$ledger_md" 2>/dev/null || stat -f %m "$ledger_md" 2>/dev/null || echo 0)
      age_secs=$(( now - mtime ))
      if [[ "$age_secs" -gt $((7 * 86400)) ]]; then
        _red "wave-e-e6-needs-you" "NEEDS-YOU.md is $((age_secs / 86400))d stale despite $open_decisions open Awaiting-decision item(s) — run: bash adapters/claude-code/scripts/needs-you.sh render"
      fi
    fi
  fi

  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

- **RED condition 1:** `ledger_state` has ≥1 open `decision`-section item AND
  `NEEDS-YOU.md` does not exist at the main-checkout root.
- **RED condition 2:** `ledger_state` has ≥1 open `decision`-section item AND
  `NEEDS-YOU.md` exists but its mtime is >7 days old (render never re-run
  since — a stale-but-present file is a subtler defect than absence: the
  operator sees an out-of-date ledger and may trust it).
- **GREEN when:** 0 open decisions (nothing to be fresh about — the "when any
  Awaiting-decision item is open" clause in the spec's own predicate wording),
  OR ≥1 open decision and `NEEDS-YOU.md` exists with mtime ≤7d.
- **Absence tolerance:** `ledger_state` itself absent (needs-you.sh never run
  on this machine) is GREEN, not RED — there is no ledger to be stale about,
  same tolerance class as E.8's nl-issues.jsonl predicate.
- **Fixture for a synthetic RED (condition 2 — stale-but-present):**
  ```bash
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/state"
  cat > "$tmp/state/ledger.json" <<'JSON'
  {"schema_version":1,"items":[{"id":"NY-fixture","section":"decision","state":"open","text":"fixture decision","session":null,"links":[],"tier":null,"created_at":"2026-06-01T00:00:00Z","updated_at":"2026-06-01T00:00:00Z","resolved_at":null,"resolution_note":null}]}
  JSON
  touch -d "10 days ago" "$tmp/NEEDS-YOU.md" 2>/dev/null || touch -t 200001010000 "$tmp/NEEDS-YOU.md"
  echo "# stale fixture" > "$tmp/NEEDS-YOU.md"
  touch -d "10 days ago" "$tmp/NEEDS-YOU.md" 2>/dev/null || touch -t 200001010000 "$tmp/NEEDS-YOU.md"
  # Running check_wave_e_e6_needs_you against HOME=$tmp, main_root=$tmp must RED.
  ```

## Predicate 3 (informational, not RED/GREEN gated) — manifest entry present

`manifest-entry.json` in this directory is the fragment E.10 merges into
`adapters/claude-code/manifest.json` at §E.W. Once merged, `manifest-check.sh`
(existing tool) is the freshness oracle for "does the manifest know about this
surface" — no additional doctor logic needed for that half; only predicates 1
and 2 above are E.6-specific additions to `harness-doctor.sh --full`.

## `has-entry-for-session` — consumption contract (for E.10's D.3 warn extension)

Per §E.0-DECISIONS point (d): the D.3 extension ("warn when a final-message
decision block lacks a same-turn NEEDS-YOU entry") is reassigned to E.10 as
the single owner of `session-honesty-gate.sh` edits this wave. This is the
exact interface E.10's warn extension calls, restated here so E.10 (and
anyone reviewing that edit) can verify against a single source of truth:

```bash
bash adapters/claude-code/scripts/needs-you.sh has-entry-for-session "$SESSION_ID"
```

- Exit 0 if the ledger has ANY **open** (unresolved) entry whose `session`
  field equals `$SESSION_ID` — regardless of section (decision, question, or
  inflight all count as "surfaced to the ledger this session").
- Exit 1 otherwise (no matching open entry, ledger absent, or ledger empty —
  all collapse to the same "nothing surfaced" answer).
- Prints nothing to stdout/stderr in either case — this is a pure predicate;
  callers read the exit code, not output. (Matches the shape of git's own
  plumbing predicates, e.g. `git diff --quiet`.)
- **Sandboxing:** set `NEEDS_YOU_STATE_DIR` to point at a fixture ledger
  directory for self-tests; never invoke against the real
  `$HOME/.claude/state/needs-you/` from a test.

## `add` — session-wrap.sh PAUSING-path call point: DOCUMENTED, NOT WIRED

Per the task brief's own escape hatch ("if session-wrap edit is risky,
document the exact insertion diff... instead — say which you did"): **this
builder documents the diff rather than applying it.** Reasoning:

`session-wrap.sh` (`adapters/claude-code/scripts/session-wrap.sh`) has **no
existing plumbing to receive the session's final-message text at all**:

- It is invoked from `settings.json.template`'s Stop chain as a bare command
  (`bash ~/.claude/scripts/session-wrap.sh refresh`) with no stdin JSON piped
  in — unlike `session-honesty-gate.sh` (same Stop chain, runs earlier),
  which receives `{"transcript_path":...,"session_id":...}` on stdin per the
  Claude Code Stop-hook input contract and is the ONE place in the chain that
  already parses out `MARKER_KEYWORD` / `MARKER_SUMMARY` (see that file's
  `marker_scan_eval()`, ~line 134: `marker_re='^[[:space:]>*_\`#-]*(DONE|PAUSING|BLOCKED|CONTINUING):[[:space:]]'`).
- `session-wrap.sh`'s own subcommands (`verify`/`refresh`) take a repo path,
  never a message string or transcript path — `cmd_verify`/`cmd_refresh`
  read `SCRATCHPAD.md`/`docs/backlog.md`/`docs/discoveries/*.md` from disk,
  nothing conversation-shaped.
- Threading the PAUSING text through would require ONE of: (a) changing
  `session-wrap.sh`'s stdin contract to also accept the Stop-hook JSON and
  re-deriving the marker text itself (duplicating `session-honesty-gate.sh`'s
  own regex — a maintenance-drift risk: two independent copies of the same
  marker pattern silently diverging), or (b) changing the
  `settings.json.template` Stop-chain entry to pipe stdin through / pass a
  new arg. Both are more than a "clean insertion point" in the existing
  function bodies — (a) risks drift with E.10's D.3 extension (owned by the
  SAME session-honesty-gate.sh this task must not touch), and (b) is a
  `settings.json.template` edit, which is ORCHESTRATOR-ONLY this wave
  (§E.0.1 rule 1) — a builder-side change to session-wrap.sh's own body
  cannot fix that half regardless.

**The exact diff, for the orchestrator (or E.10, since they already own the
Stop-chain's marker-parsing logic) to apply at §E.W integration**, once the
transcript/marker text is available to whichever hook calls this:

```diff
--- a/adapters/claude-code/scripts/session-wrap.sh
+++ b/adapters/claude-code/scripts/session-wrap.sh
@@ usage() cat <<EOF block @@
 Usage:
   session-wrap.sh verify           Verify freshness; exit 0 if fresh, 2 if stale.
   session-wrap.sh refresh          Apply mechanical refreshes, then verify.
+  session-wrap.sh pausing-add <session-id> <exact-ask-text>
+                                   Called when the turn's final marker is
+                                   PAUSING: — records <exact-ask-text> to
+                                   NEEDS-YOU.md's Awaiting-decision section
+                                   via needs-you.sh, then verifies as usual.
   session-wrap.sh --self-test      Run internal scenarios.

@@ new subcommand function, alongside cmd_verify/cmd_refresh @@
+# cmd_pausing_add — record the PAUSING: marker's exact ask to NEEDS-YOU.md
+# before the usual verify/refresh. No-op (never blocks) if needs-you.sh is
+# not present at the expected path — this call point must never be the
+# reason a Stop hook fails, matching this file's own non-blocking-writer
+# posture everywhere else.
+cmd_pausing_add() {
+  local session_id="$1" ask_text="$2"
+  local repo; repo="$(find_repo_root)" || return 0
+  local ny="${repo}/adapters/claude-code/scripts/needs-you.sh"
+  [[ -x "$ny" ]] || return 0
+  bash "$ny" add --section decision --text "$ask_text" --session "$session_id" >/dev/null 2>&1 || true
+}

@@ main dispatch case statement @@
   refresh)
     REPO="$(find_repo_root)" || { echo "session-wrap: not in a git repo, skipping" >&2; exit 0; }
     WT_REPO="$(find_worktree_root)" || WT_REPO="$REPO"
     cmd_refresh "$REPO" "$WT_REPO"
     ;;
+  pausing-add)
+    shift
+    cmd_pausing_add "$1" "$2"
+    REPO="$(find_repo_root)" || { echo "session-wrap: not in a git repo, skipping" >&2; exit 0; }
+    WT_REPO="$(find_worktree_root)" || WT_REPO="$REPO"
+    cmd_refresh "$REPO" "$WT_REPO"
+    ;;
```

The remaining half of this wiring — WHO calls `session-wrap.sh pausing-add
<session-id> "<ask>"` with the actual marker text, extracted from the
transcript — is exactly the same problem E.10's D.3 extension already has to
solve inside `session-honesty-gate.sh` (it already has `MARKER_KEYWORD` /
`MARKER_SUMMARY` in scope right after `marker_scan_eval`). The natural
integration is a same-Stop-chain call from `session-honesty-gate.sh` itself
(or a small new line in its post-parse block) invoking:

```bash
if [[ "$MARKER_KEYWORD" == "PAUSING" ]]; then
  bash "${REPO_ROOT}/adapters/claude-code/scripts/needs-you.sh" add \
    --section decision --text "$MARKER_SUMMARY" --session "$SESSION_ID" >/dev/null 2>&1 || true
fi
```

— rather than routing through session-wrap.sh's `refresh` call at all, since
session-honesty-gate.sh already has every value needed and runs in the same
Stop chain. This builder flags BOTH options (session-wrap.sh subcommand vs.
a direct call from session-honesty-gate.sh) for E.10/the orchestrator to pick
between at §E.W, since either satisfies the spec's "add called by... 
session-wrap when a turn ends PAUSING" requirement functionally (the operator-
visible outcome — a NEEDS-YOU.md entry appears — is identical either way);
this builder does not have write access to session-honesty-gate.sh to choose
for them.

## Consumption contract summary (for E.1 and E.10 reviewers)

- **E.1 (`session-start-digest.sh`) consumes:** the spec's own line ("digest
  (E.1) links the file + open count") — no needs-you.sh verb is required for
  this; E.1 can grep/jq the rendered `NEEDS-YOU.md` or the JSON ledger state
  directly at `$HOME/.claude/state/needs-you/ledger.json` (`.items[] |
  select(.state=="open") | length` for the open-count half, tolerate-absent
  if the ledger has never been initialized on the machine).
- **E.10 (session-honesty-gate.sh D.3 extension) consumes:**
  `needs-you.sh has-entry-for-session <session-id>` — see above.
- **Sandboxing env vars (self-tests / any consumer's own `--self-test`
  fixtures should use these, never real machine state):**
  - `NEEDS_YOU_STATE_DIR` — overrides the ledger state directory
    (default `$HOME/.claude/state/needs-you/`).
  - `NEEDS_YOU_MD_PATH` — overrides the rendered `NEEDS-YOU.md` path
    (default `<main-checkout-root>/NEEDS-YOU.md`).
  - `HARNESS_SELFTEST=1` — if neither override above is set, routes both to
    sandboxed paths under `${TMPDIR:-/tmp}/needs-you-selftest/<pid>/` (same
    pattern as `nl-issue.sh` / `lib/signal-ledger.sh`).

## Environment note (for whoever next runs this script's --self-test)

On the machine this task was built on (a shared Windows box running several
concurrent Claude Code sessions/worktrees), `needs-you.sh --self-test`
intermittently appeared to HANG under a short timeout (40-45s), with jq
emitting `jq: error: writing output failed: Invalid argument` mid-run. Root-
caused via: (1) an identical bare `jq` subprocess loop with no needs-you.sh
code involved reproduced the same stall under contention; (2) the pre-existing
`decision-queue.sh --self-test` (already on this branch's base, same jq-heavy
architecture) hit the IDENTICAL failure signature independently; (3) a
120-second timeout run of `needs-you.sh --self-test` completed cleanly (19/19
PASS, exit 0) on the same machine once system-wide process load eased — this
box's `ulimit -u` is a fixed 256 (soft AND hard), shared across every
concurrent session/worktree process tree. Conclusion: this is a transient,
external, machine-level resource-contention artifact of jq-subprocess-heavy
scripts on this specific shared Windows/Git-Bash environment, NOT a defect in
needs-you.sh's logic (every verb was additionally verified correct via
targeted, isolated, single-call manual tests during development, independent
of the full self-test's cumulative jq-call count). If a future run of
`--self-test` appears to hang, retry with a longer wall-clock budget (≥90s)
before suspecting a logic regression.
