# O.2 call-site fragment — session-heartbeat.sh touch call-lines

Status: FOR ORCHESTRATOR SPLICE ONLY. Per specs-o §O.0.2 dispatch map, O.1
owns `hooks/session-start-digest.sh`, `hooks/workstreams-stop-writer.sh`,
and `hooks/pre-compact-continuity.sh` this batch — O.2 (this builder) does
NOT edit those files. This fragment names the exact one-line splice for
each, for the orchestrator to apply after both O.1 and O.2 land.

All three call-lines are **best-effort, never-blocking**
(`scripts/session-heartbeat.sh touch` itself never exits non-zero — see
that script's header) — safe to add without any error-handling wrapper
beyond what's shown (the `|| true` / backgrounding below is defense in
depth, not load-bearing, since the script already guarantees exit 0).

Resolve the heartbeat script path via `nl-paths.sh`-style resolution or a
simple relative path from the hook's own `HOOKS_DIR`/`SCRIPT_DIR` (both
`scripts/` and `hooks/` are siblings under `adapters/claude-code/`):

```bash
"$HOOKS_DIR/../scripts/session-heartbeat.sh"
```

---

## 1. `hooks/session-start-digest.sh` — session-start event

**Where:** inside `run_digest()`, before the first `feed_*` call (session
start is a lifecycle boundary, not a feed line — it should fire regardless
of whether any feed produces output). Current top of the function (see
`run_digest` at line ~915):

```bash
run_digest() {
  local cwd="${1:-$PWD}"
  local alert_dir="${2:-$(_alert_dir_default)}"
  local seen_path; seen_path="${3:-$(_digest_seen_path)}"
  local input="${DIGEST_STDIN:-}"

  local -a lines=()
```

**Splice — add immediately after the `local -a lines=()` line:**

```bash
  # O.2: session-start liveness heartbeat (best-effort, never blocks).
  "$HOOKS_DIR/../scripts/session-heartbeat.sh" touch --event start >/dev/null 2>&1 || true
```

(`HOOKS_DIR` is already defined earlier in this file at line ~65 as
`$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`.)

## 2. `hooks/workstreams-stop-writer.sh` — turn-end event + scanned marker

**Where:** this file is a chain aggregator (`MEMBERS=(...)` array, each
member invoked in the `for spec in "${MEMBERS[@]}"` loop, output demoted to
a ledger `warn`). The heartbeat touch is NOT itself a chain member in the
`MEMBERS` array sense (it doesn't need the same-input-on-stdin treatment
and must never itself be captured/demoted to a warn on non-empty stdout,
since `touch` prints nothing on success) — splice it as a **standalone
call after the member loop**, so it fires once per Stop regardless of
member outcomes:

```bash
for spec in "${MEMBERS[@]}"; do
  f="${spec%% *}"
  args="${spec#"$f"}"
  # shellcheck disable=SC2086
  out=$(printf '%s' "$INPUT" | bash "$HOOKS_DIR/$f" $args 2>&1 || true)
  if [[ -n "$out" ]] && command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "${f%.sh}" "warn" "stop-writer: ${out:0:200}"
  fi
done

exit 0
```

**Splice — insert before `exit 0`:**

```bash
# O.2: turn-end liveness heartbeat, marker_state from the final assistant
# message scan (same regex family as session-honesty-gate.sh's
# MARKER_KEYWORD: DONE|PAUSING|BLOCKED|CONTINUING). $INPUT is the Stop
# hook's stdin JSON (already captured above); this chain does not currently
# scan the transcript for the terminal marker itself, so the exact
# extraction call depends on what O.1's own Stop-time scan already computes
# — if session-honesty-gate.sh (or another already-firing Stop member) has
# already derived MARKER_KEYWORD for this same stdin, reuse that value;
# otherwise pass "none" (the heartbeat's marker_state is best-effort
# metadata, not a re-implementation of session-honesty's parsing — a "none"
# here still lets sweep/od_sessions classify liveness correctly, only the
# marker_state field itself would read "none" until wired to a real scan).
marker_state="${SESSION_HEARTBEAT_MARKER_STATE:-none}"
"$HOOKS_DIR/../scripts/session-heartbeat.sh" touch --event turn-end --marker "$marker_state" >/dev/null 2>&1 || true
```

Orchestrator note: if `session-honesty-gate.sh` already runs earlier in
the Stop chain and exports/prints its scanned `MARKER_KEYWORD`, wire
`SESSION_HEARTBEAT_MARKER_STATE` from that value at integration time
instead of defaulting to `"none"` — this fragment intentionally leaves that
wire as an orchestrator decision since it touches a file O.2 does not own
and whose exact Stop-chain ordering vs session-honesty-gate.sh is outside
this task's file scope.

## 3. `hooks/pre-compact-continuity.sh` — compact event

**Where:** inside `_run_live()`, after the real snapshot work
(`_run_precompact`) and before the function's own `exit 0` (line ~244):

```bash
_run_live() {
  local input
  input="${CLAUDE_TOOL_INPUT:-}"
  if [ -z "$input" ] && [ ! -t 0 ]; then
    input="$(cat 2>/dev/null || echo "")"
  fi
  [ -z "$input" ] && exit 0

  command -v jq >/dev/null 2>&1 || exit 0
  jq -e . >/dev/null 2>&1 <<<"$input" || exit 0

  local transcript session_id trigger
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  trigger="$(printf '%s' "$input" | jq -r '.trigger // empty' 2>/dev/null)"

  _run_precompact "$transcript" "$session_id" "$_SNAPSHOT_SCRIPT_DEFAULT" "$trigger"
  exit 0
}
```

**Splice — insert immediately before the final `exit 0`:**

```bash
  # O.2: compact-event liveness heartbeat (best-effort, never blocks).
  "$SCRIPT_DIR/../scripts/session-heartbeat.sh" touch --event compact >/dev/null 2>&1 || true
  exit 0
}
```

(Verified: `pre-compact-continuity.sh` line 105 defines
`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` — the literal
`SCRIPT_DIR` name above is correct as written, no substitution needed.)

---

## Note on `resume` event

specs-o §O.2 lists `resume` as a valid `--event` value, but the dispatch
map's three named call-sites (session-start-digest.sh, the stop-writer
chain, pre-compact-continuity.sh) do not include a dedicated "session
resumed" hook. Per §O.1's deliverable 2, `session-resume` is already
emitted by the existing resumer (`scripts/session-resumer.sh`) via
`ledger_emit`, normalized to the C2 event name. Whether the resumer ALSO
gains a `session-heartbeat.sh touch --event resume` call-line is an O.1/O.3
orchestrator integration decision (the resumer file is not in either O.1's
or O.2's owned-files list per the dispatch map) — flagged here as an
**orchestrator TODO**, not silently dropped.
