# O.6 doctor-predicate fragment

NL Observability Program Wave O, task O.6 (specs-o §O.6). Six complete
`check_*()` bash functions for `harness-doctor.sh`, ready for the
orchestrator to paste in verbatim (per specs-o §O.0.1: the doctor itself
is orchestrator-only; builders ship the check bodies as fragments). Each
function follows the file's existing idiom exactly:

- Signature `check_x() { local live_home="$1" repo_root="$2"; ... }`
  (both params present even when a check only needs one, matching
  `check_heartbeat_task`/`check_untracked_dirt_ignore_rule`'s own
  pattern of accepting both and using what it needs).
- `_red "<check-id>" "<detail>"` / `_warn "<check-id>" "<detail>"` for
  verdicts; every function ends `CHECKS_RUN=$((CHECKS_RUN + 1))`.
- Tolerate-absent WARN (never RED) when the surface being checked has
  simply never been installed on this machine/fixture — mirrors
  `check_wave_e_surfaces`'s E.1/E.7/E.8/E.9 sub-checks.
- Every RED/WARN detail names the concrete remediation command where one
  exists.

**Orchestrator integration steps:**
1. Paste the six functions below into `harness-doctor.sh` (suggested
   placement: immediately after `check_untracked_dirt_ignore_rule`, before
   `check_pin_f_waiver_purpose_clauses`).
2. Add all six calls to `run_quick_checks()`'s call list (after
   `check_untracked_dirt_ignore_rule "$live_home" "$repo_root"`).
3. Add one RED-fixture + one GREEN-fixture self-test scenario per check
   into the `--self-test` handler block (scenario descriptions below;
   written to the same standard as the existing wave-e self-test
   scenarios in this file — mktemp -d sandbox, `HARNESS_DOCTOR_HOME`/
   `NL_REPO_ROOT` env vars, assert on `[doctor] RED <id>` / absence of RED
   in stdout).

---

## 1. `check_obs_writers_firing`

Ledger mtime <24h AND line-count grew since the doctor's own last-seen
stamp. This is a "is anything actually emitting" liveness check — a
ledger that exists but has gone stale/stopped-growing means every writer
upstream silently died (the exact RC4 "0%-signal-consumption" failure
mode the design sketch's law 2 exists to catch, one layer earlier: law 2
catches unmapped event TYPES, this catches a pipeline that stopped
emitting ANY events at all).

**Stamp file** (this check's own tiny state, NOT the manifest/doctor
cache — a fresh idea this task introduces, described here so the
orchestrator can review it before landing): `${live_home}/state/doctor-cache/obs-ledger-stamp.txt`,
one line: `<mtime-epoch> <line-count>` from the PREVIOUS run. Written by
this check itself, at the END of every invocation (self-updating stamp —
mirrors no existing doctor pattern verbatim, but follows the same
"doctor writes its own small housekeeping state under live_home/state"
shape as `check_wave_e_surfaces`'s E.9 handoff-dir writability probe).
First-ever run (stamp absent) always passes this check (nothing to
compare growth against yet) and just writes the initial stamp — same
"first observation seeds the baseline, does not fail" posture as any
delta-based check with no prior sample.

```bash
check_obs_writers_firing() {
  local live_home="$1" repo_root="$2"
  local ledger="${live_home}/state/signal-ledger.jsonl"

  if [[ ! -f "$ledger" ]]; then
    _warn "obs-writers-firing" "signal ledger not found at ${ledger} — observability pipeline not yet installed/run on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local now_epoch mtime_epoch age_hours
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)
  mtime_epoch=$(stat -c %Y "$ledger" 2>/dev/null || stat -f %m "$ledger" 2>/dev/null || echo 0)
  age_hours=$(( (now_epoch - mtime_epoch) / 3600 ))

  if [[ "$age_hours" -gt 24 ]]; then
    _red "obs-writers-firing" "signal ledger ${ledger} has not been written to in ${age_hours}h (budget 24h) — every ledger writer may have silently stopped firing; check session-start-digest.sh/stop-verdict-dispatcher.sh/workstreams-stop-writer.sh wiring"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local line_count
  line_count=$(wc -l < "$ledger" 2>/dev/null | tr -d ' ')
  [[ -n "$line_count" ]] || line_count=0

  local stamp_dir="${live_home}/state/doctor-cache"
  local stamp_file="${stamp_dir}/obs-ledger-stamp.txt"
  mkdir -p "$stamp_dir" 2>/dev/null || true

  if [[ ! -f "$stamp_file" ]]; then
    printf '%s %s\n' "$mtime_epoch" "$line_count" > "$stamp_file" 2>/dev/null || true
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local prev_mtime prev_lines
  read -r prev_mtime prev_lines < "$stamp_file" 2>/dev/null
  prev_mtime="${prev_mtime:-0}"
  prev_lines="${prev_lines:-0}"

  if [[ "$mtime_epoch" -le "$prev_mtime" || "$line_count" -le "$prev_lines" ]]; then
    _red "obs-writers-firing" "signal ledger ${ledger} has NOT grown since the last doctor check (was ${prev_lines} lines at mtime ${prev_mtime}, now ${line_count} lines at mtime ${mtime_epoch}) despite being <24h old — writers may be looping without emitting, or the file was truncated/rotated without the rotation being reflected here"
  fi

  printf '%s %s\n' "$mtime_epoch" "$line_count" > "$stamp_file" 2>/dev/null || true
  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

**RED fixture:** mktemp -d sandbox; `HARNESS_DOCTOR_HOME=$D/live`. Write
`$D/live/state/signal-ledger.jsonl` with a few lines, `touch` it to now.
Write `$D/live/state/doctor-cache/obs-ledger-stamp.txt` containing
`<now_epoch+100> <line_count+5>` (a stamp claiming MORE lines / a LATER
mtime than the real file currently has) — this forces the
not-grown-since-last-check branch. Assert `[doctor] RED obs-writers-firing`
appears.

**GREEN fixture:** same ledger file, but no pre-existing stamp file (or a
stamp with fewer lines / earlier mtime than current) — first-run or
genuine-growth case. Assert no RED for this check-id.

---

## 2. `check_obs_heartbeats_fresh`

Every session with a transcript mtime <30min must have a heartbeat file
<30min old (else RED naming the stale/missing sids). Zero live sessions
(no transcripts <30min) is GREEN — an idle machine is not a broken
pipeline.

Transcript discovery: `~/.claude/projects/*/​*.jsonl` is the real Claude
Code transcript location; this check accepts an override
`OBS_TRANSCRIPTS_DIR` (mirrors the other C1-consuming surfaces' env-var
override convention) so self-test fixtures never touch the real
`~/.claude/projects` tree, and resolves the session id from the
transcript's basename (`<session-id>.jsonl`) — the same id shape
`CLAUDE_CODE_SESSION_ID` populates and heartbeat files are keyed by.

```bash
check_obs_heartbeats_fresh() {
  local live_home="$1" repo_root="$2"
  local hb_dir="${live_home}/state/heartbeats"
  local transcripts_dir="${OBS_TRANSCRIPTS_DIR:-${HOME:-}/.claude/projects}"

  if [[ ! -d "$transcripts_dir" ]]; then
    _warn "obs-heartbeats-fresh" "no transcripts directory at ${transcripts_dir} — nothing to check (zero live sessions)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local now_epoch
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)

  local -a live_sids=()
  local f mtime age_min sid
  while IFS= read -r -d '' f; do
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    age_min=$(( (now_epoch - mtime) / 60 ))
    if [[ "$age_min" -lt 30 ]]; then
      sid="$(basename "$f" .jsonl)"
      live_sids+=("$sid")
    fi
  done < <(find "$transcripts_dir" -type f -name '*.jsonl' -print0 2>/dev/null)

  if [[ "${#live_sids[@]}" -eq 0 ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  if [[ ! -d "$hb_dir" ]]; then
    _red "obs-heartbeats-fresh" "${#live_sids[@]} session(s) have a transcript <30min old but no heartbeat directory exists at ${hb_dir} — session-heartbeat.sh touch is not wired or O.2 is not installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local -a stale_sids=()
  for sid in "${live_sids[@]}"; do
    local hbf="${hb_dir}/${sid}.json"
    if [[ ! -f "$hbf" ]]; then
      stale_sids+=("${sid}:missing")
      continue
    fi
    local hb_mtime hb_age_min
    hb_mtime=$(stat -c %Y "$hbf" 2>/dev/null || stat -f %m "$hbf" 2>/dev/null || echo 0)
    hb_age_min=$(( (now_epoch - hb_mtime) / 60 ))
    if [[ "$hb_age_min" -ge 30 ]]; then
      stale_sids+=("${sid}:${hb_age_min}min")
    fi
  done

  if [[ "${#stale_sids[@]}" -gt 0 ]]; then
    _red "obs-heartbeats-fresh" "$(IFS=,; echo "${stale_sids[*]}") — session(s) with a transcript <30min old have a missing/stale (>=30min) heartbeat file; the heartbeat writer may not be wired into this session's chain (see tests/fixtures/wave-o/O.2/callsite-wiring.md)"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

**RED fixture:** mktemp -d sandbox. `OBS_TRANSCRIPTS_DIR=$D/transcripts`;
write `$D/transcripts/proj/sess-live.jsonl`, touch to now (fresh
transcript). `HARNESS_DOCTOR_HOME=$D/live`; do NOT create
`$D/live/state/heartbeats/sess-live.json` (missing heartbeat for a live
session). Assert `[doctor] RED obs-heartbeats-fresh` naming
`sess-live:missing`.

**GREEN fixture:** same fresh transcript, but also write
`$D/live/state/heartbeats/sess-live.json` (any valid content) and touch
it to now. Assert no RED for this check-id. Also cover the "zero live
sessions" GREEN: no transcripts <30min at all (dir empty or all old) —
assert no RED/WARN-as-failure for this check-id.

---

## 3. `check_obs_scheduled_tasks`

SCHEDULED-TASK-HEALTH-01: every registered NL-owned task (via
`scripts/scheduled-task-health.sh list`) has Last Result in
`{0, 267009, 267011}`; else RED naming the task + code. A task that is
simply not registered stays the EXISTING WARN semantics
(`check_heartbeat_task`'s own posture) — this predicate does not
duplicate that WARN, it only judges tasks the health script actually
reports (i.e. ones that DO exist).

```bash
check_obs_scheduled_tasks() {
  local live_home="$1" repo_root="$2"
  local script=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/scripts/scheduled-task-health.sh" ]] \
    && script="${repo_root}/adapters/claude-code/scripts/scheduled-task-health.sh"
  [[ -z "$script" && -f "${live_home}/scripts/scheduled-task-health.sh" ]] \
    && script="${live_home}/scripts/scheduled-task-health.sh"

  if [[ -z "$script" ]]; then
    _warn "obs-scheduled-tasks" "scheduled-task-health.sh missing — O.6 not yet installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v schtasks >/dev/null 2>&1 && [[ -z "${SCHTASKS_CMD:-}" ]]; then
    _warn "obs-scheduled-tasks" "schtasks not available on this platform — scheduled-task health check skipped (non-Windows)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out
  out="$(bash "$script" list 2>/dev/null)"
  if [[ -z "$out" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local line name code bad=0
  while IFS=$'\t' read -r name code; do
    [[ -z "$name" ]] && continue
    case "$code" in
      0|267009|267011) ;;
      *)
        _red "obs-scheduled-tasks" "task '${name}' Last Result=${code} (expected one of 0/267009/267011) — check the task's registered command path; run: MSYS_NO_PATHCONV=1 schtasks /Query /V /FO LIST /TN \"${name}\""
        bad=1
        ;;
    esac
  done <<< "$out"

  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

**RED fixture:** mktemp -d sandbox with a stub
`scheduled-task-health.sh` (or set `NL_REPO_ROOT`/copy the real script
into the fixture repo tree) and `SCHTASKS_CMD` set so `scheduled-task-health.sh list`
prints `NL-fixture-task<TAB>-2147024894`. Assert `[doctor] RED obs-scheduled-tasks`
naming `NL-fixture-task` and `-2147024894`.

**GREEN fixture:** same wiring, `SCHTASKS_CMD` output
`NL-fixture-task<TAB>0`. Assert no RED for this check-id. Also cover the
absent-script WARN (no `scheduled-task-health.sh` in the fixture repo at
all) as a second GREEN-shaped (WARN, not RED) scenario.

---

## 4. `check_obs_consumer_map`

Contract C3's enforcing predicate, two-sided:
(a) every event type observed in the ledger's last 1000 lines has an
entry in `observability-consumer-map.json`;
(b) every literal event-type string passed as the SECOND argument to
`ledger_emit`/`ledger_emit_typed` anywhere in the repo has an entry;
(c) every entry in the map has >=1 consumer listed.
Unknown-in-map = RED naming the type.

Literal-scan caveat (documented, not silently ignored; UPDATED after
livesmoke against the real repo — see below): this predicate can only
see STATICALLY LITERAL event-type arguments (`ledger_emit "gate" "event-name" "..."`).
Several REAL, PRE-EXISTING call sites pass a variable as the second
argument instead of a literal (`ledger_emit "stop-verdict-dispatcher" "$event" "$detail"`
in stop-verdict-dispatcher.sh, `ledger_emit "work-integrity-gate" "$event" "$detail"`
in work-integrity-gate.sh, `ledger_emit "resumer" "$normalized" "..."` in
session-resumer.sh, `ledger_emit "test-gate" "$ev"` / `ledger_emit_typed "test-gate-o1" "$ev"`
in test-gate.sh's own self-test) — a naive scan that just captures the
second quoted group verbatim will "discover" bogus event-type names like
`$ev`/`$event`/`$normalized` and RED on them as false unmapped types.
The scan below FILTERS these out (skips any captured group starting with
`$`, since a variable reference is never a valid static event-type
literal) rather than reporting them — this is a real bug found and fixed
during this task's own livesmoke (see report-back), not a hypothetical.
The residual limitation (a dynamic call site's REAL runtime event values
are invisible to a static grep) stands: `stop-verdict-dispatcher.sh`,
`work-integrity-gate.sh`, and `session-resumer.sh`'s dynamically-named
events must be covered in the consumer map by their own dedicated
map-authoring pass (the map already covers `resumer`'s normalized output
vocabulary per O.1's session-resume/throttle-detected entries; this
predicate cannot verify that coverage mechanically for variable-named
call sites — a known, named gap, not silently swallowed).

**LIVESMOKE FINDING (real, against this machine's real ledger + real
map, orchestrator TODO):** with both fixes applied, running this
predicate against the real `$HOME/.claude/state/signal-ledger.jsonl` and
the real `observability-consumer-map.json` on this machine produces ONE
genuine RED: `unmapped ledger event type(s): classify-skip,protocol-downgrade,stop-cycle,would-have-resumed`.
All four are real, currently-emitted event names —
`session-resumer.sh`'s own normalized vocabulary (`classify-skip`,
`would-have-resumed`, emitted via `ledger_emit "resumer" "$normalized" ...`)
and `stop-verdict-dispatcher.sh`'s own vocabulary (`stop-cycle`,
`protocol-downgrade`, emitted via its `_svd_ledger` wrapper around
`ledger_emit "stop-verdict-dispatcher" "$event" "$detail"`) — that O.1's
map does not enumerate (the map covers the frozen C2 vocabulary plus the
8 pre-existing gate-outcome classes, not these two hooks' own
finer-grained event names, which pre-date Wave O). This is exactly the
class of gap law 2 / this predicate exists to catch; it is a real,
today, on-this-machine finding, not a fixture artifact. Orchestrator TODO:
add these 4 entries to `observability-consumer-map.json` (each needs a
real consumer named — at minimum `digest:feed_ledger_summary`, since the
existing digest already renders arbitrary ledger events) before this
predicate can go GREEN on this machine.

```bash
check_obs_consumer_map() {
  local live_home="$1" repo_root="$2"
  local map=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/observability-consumer-map.json" ]] \
    && map="${repo_root}/adapters/claude-code/observability-consumer-map.json"
  [[ -z "$map" && -f "${live_home}/observability-consumer-map.json" ]] \
    && map="${live_home}/observability-consumer-map.json"

  if [[ -z "$map" ]]; then
    _warn "obs-consumer-map" "observability-consumer-map.json not found — O.1 not yet installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _warn "obs-consumer-map" "jq not available — cannot verify observability-consumer-map.json coverage"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! jq -e . "$map" >/dev/null 2>&1; then
    _red "obs-consumer-map" "${map} is not valid JSON"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # (c) every map entry has >=1 consumer
  local empty_entries
  empty_entries="$(jq -r '.event_types | to_entries[] | select((.value.consumers // []) | length == 0) | .key' "$map" 2>/dev/null)"
  if [[ -n "$empty_entries" ]]; then
    _red "obs-consumer-map" "event type(s) with zero consumers in ${map}: $(printf '%s' "$empty_entries" | tr '\n' ',' | sed 's/,$//')"
  fi

  # (a) every ledger-observed event type (last 1000 lines) is in the map.
  # `tr -d '\r'` on the jq output is REQUIRED (not defensive-paranoia): the
  # real machine's signal-ledger.jsonl round-trips through jq with CRLF
  # line endings on this platform (verified live — see report-back), so
  # `read -r ev` without the strip captures "block\r" and silently never
  # matches the map's "block" key, RED-ing every real event type as a
  # false unmapped positive (findings 030/038-class bug; caught by this
  # task's own livesmoke, not hypothetical).
  local ledger="${live_home}/state/signal-ledger.jsonl"
  if [[ -f "$ledger" ]]; then
    local unmapped_ledger
    unmapped_ledger="$(tail -n 1000 "$ledger" 2>/dev/null | jq -r '.event // empty' 2>/dev/null | tr -d '\r' | sort -u | while read -r ev; do
      [[ -z "$ev" ]] && continue
      jq -e --arg e "$ev" '.event_types | has($e)' "$map" >/dev/null 2>&1 || echo "$ev"
    done)"
    if [[ -n "$unmapped_ledger" ]]; then
      _red "obs-consumer-map" "ledger event type(s) observed in last 1000 lines but absent from ${map}: $(printf '%s' "$unmapped_ledger" | tr '\n' ',' | sed 's/,$//')"
    fi
  fi

  # (b) every literal ledger_emit(_typed) 2nd-arg literal in the repo is in
  # the map. `grep -vE '^\$'` after the sed capture is REQUIRED (not
  # defensive-paranoia): several real pre-existing call sites pass a
  # VARIABLE as the 2nd argument (`ledger_emit "stop-verdict-dispatcher" "$event" "$detail"`,
  # `ledger_emit "work-integrity-gate" "$event" "$detail"`,
  # `ledger_emit "resumer" "$normalized" "..."`, `ledger_emit "test-gate" "$ev"`)
  # — without this filter the sed capture group is the literal text
  # "$event"/"$ev"/"$normalized" and this predicate REDs on bogus
  # "unmapped event type '$ev'" noise (caught by this task's own
  # livesmoke). A variable-named call site's REAL runtime event values
  # are invisible to this static scan — documented residual limitation,
  # not silently swallowed (see this fragment's caveat section above).
  if [[ -n "$repo_root" ]]; then
    local unmapped_repo
    unmapped_repo="$(grep -rhoE 'ledger_emit(_typed)?[[:space:]]+"[^"]*"[[:space:]]+"[^"]*"' \
        "${repo_root}/adapters/claude-code/hooks" "${repo_root}/adapters/claude-code/scripts" 2>/dev/null \
      | sed -E 's/ledger_emit(_typed)?[[:space:]]+"[^"]*"[[:space:]]+"([^"]*)"/\2/' \
      | grep -vE '^\$' \
      | sort -u | while read -r ev; do
        [[ -z "$ev" ]] && continue
        jq -e --arg e "$ev" '.event_types | has($e)' "$map" >/dev/null 2>&1 || echo "$ev"
      done)"
    if [[ -n "$unmapped_repo" ]]; then
      _red "obs-consumer-map" "literal ledger_emit event type(s) found in repo source but absent from ${map}: $(printf '%s' "$unmapped_repo" | tr '\n' ',' | sed 's/,$//')"
    fi
  fi

  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

**RED fixture:** mktemp -d sandbox repo (`NL_REPO_ROOT=$D/repo`,
`HARNESS_DOCTOR_HOME=$D/live`). Write
`$D/repo/adapters/claude-code/observability-consumer-map.json` with
`{"schema":1,"event_types":{"block":{"consumers":["digest:x"]}}}`
(missing `warn` and any others). Write a fixture hook under
`$D/repo/adapters/claude-code/hooks/fixture-hook.sh` containing a line
`ledger_emit "my-gate" "warn" "detail"`. Assert `[doctor] RED obs-consumer-map`
naming `warn`. Separately (or same fixture), add an entry with an empty
`consumers` array and assert it's named too.

**GREEN fixture:** map's `event_types` covers every literal 2nd-arg found
under the fixture repo's hooks/scripts dirs (including the fixture hook's
`warn`), every entry has >=1 consumer, and either no ledger file exists or
its `.event` values are a subset of the map's keys. Assert no RED for
this check-id.

---

## 5. `check_obs_cockpit_fresh`

WARN (not RED) — per specs-o §O.6 exactly. GREEN when the cockpit is
intentionally not running (optional per machine, per the design sketch's
non-goals). The condition this predicate is FOR: the cockpit IS
registered for autostart AND sessions are live, but its derived-cache
stamp is stale (>1h) — meaning the autostart claim is a lie (RC4-shaped:
a surface claimed as "on" that has actually stopped updating). Because
the plan requires WARN not RED here even in the failure case, this is a
softer signal than the other five — a max-severity WARN, never a RED,
so it never blocks `doctor --quick`'s exit code the way the others can.

Cockpit path: `workstreams-ui/server/` at repo root (§O.4's declared
path; not yet built as of O.6 — the tolerate-absent branch below is the
expected, common case pre-O.4). Autostart-registered signal: reuses the
same `NL-workstreams-heartbeat`-style scheduled-task convention — this
predicate checks for a `NL-workstreams-cockpit` task (the name §O.4's
autostart registration is expected to use, matching the `NL-*` family);
if that task is not registered, that IS "cockpit not running", i.e.
GREEN, not a failure to detect.

```bash
check_obs_cockpit_fresh() {
  local live_home="$1" repo_root="$2"
  local cockpit_dir=""
  [[ -n "$repo_root" && -d "${repo_root}/workstreams-ui/server" ]] \
    && cockpit_dir="${repo_root}/workstreams-ui/server"

  if [[ -z "$cockpit_dir" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local registered=0
  if command -v schtasks >/dev/null 2>&1; then
    MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-workstreams-cockpit" >/dev/null 2>&1 && registered=1
  fi
  if [[ "$registered" -eq 0 ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local hb_dir="${live_home}/state/heartbeats"
  local now_epoch any_live=0
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)
  if [[ -d "$hb_dir" ]]; then
    local f mtime age_min
    while IFS= read -r -d '' f; do
      mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
      age_min=$(( (now_epoch - mtime) / 60 ))
      [[ "$age_min" -lt 30 ]] && any_live=1
    done < <(find "$hb_dir" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)
  fi
  if [[ "$any_live" -eq 0 ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local stamp="${live_home}/state/workstreams-cache/derived-cache-stamp.txt"
  if [[ ! -f "$stamp" ]]; then
    _warn "obs-cockpit-fresh" "cockpit registered for autostart (NL-workstreams-cockpit) and sessions are live, but no derived-cache stamp found at ${stamp} — cockpit server may not be running or has never refreshed"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local stamp_mtime stamp_age_min
  stamp_mtime=$(stat -c %Y "$stamp" 2>/dev/null || stat -f %m "$stamp" 2>/dev/null || echo 0)
  stamp_age_min=$(( (now_epoch - stamp_mtime) / 60 ))
  if [[ "$stamp_age_min" -gt 60 ]]; then
    _warn "obs-cockpit-fresh" "cockpit derived-cache stamp is ${stamp_age_min}min old (budget 60min) while sessions are live and autostart is registered — cockpit may be stalled; check workstreams-ui/server process"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

**RED-analog fixture (WARN, per the plan's own instruction this check is
never RED):** mktemp -d sandbox repo with `$D/repo/workstreams-ui/server/`
present (any file inside so the dir exists); stub `schtasks` (or run only
where the real `schtasks` reports the fixture task — practically, this
scenario should inject via a small wrapper directory prepended to PATH
that provides a fake `schtasks` shell function/script honoring `/Query
/TN "NL-workstreams-cockpit"` as a success, since this predicate does not
have its own SCHTASKS_CMD-style override — see note below); a live
heartbeat file <30min old in `$D/live/state/heartbeats/`; a
derived-cache stamp file touched to 2h ago. Assert `[doctor] WARN obs-cockpit-fresh`.

*Implementation note for the orchestrator:* this predicate calls
`schtasks` directly (not through `scheduled-task-health.sh`), so its
self-test scenarios need a PATH-prepended fake `schtasks` (a tiny script
exiting 0 for the `NL-workstreams-cockpit` query) rather than an env-var
override — flag this as a possible follow-up to add an override var
(e.g. `OBS_COCKPIT_TASK_REGISTERED_CMD`) if the orchestrator finds the
PATH-fake approach awkward inside the existing self-test harness.

**GREEN fixture (the common case):** no `workstreams-ui/server` directory
in the fixture repo at all (O.4 not installed) — assert no WARN/RED for
this check-id. Also cover: cockpit dir present but task not registered
(schtasks query fails) — also GREEN.

---

## 6. `check_needs_you_headers`

E6-HEADER-HARDENING-01: when the needs-you ledger's open decision-count
is >0, `NEEDS-YOU.md` must contain all 4 `NY_CANONICAL_HEADERS` (from
`scripts/needs-you.sh` ~line 447). Gated on `ny_open>0`, same posture as
the existing E.6 staleness check in `check_wave_e_surfaces` (which this
predicate sits alongside, reusing its exact `ny_state`/`ny_md`/`ny_open`
resolution — copy those three local variables' resolution logic verbatim
rather than re-deriving them, so the two E.6-family checks never drift
on what "the ledger" and "the rendered file" mean).

```bash
check_needs_you_headers() {
  local live_home="$1" repo_root="$2"

  local ny_nlpaths="${repo_root}/adapters/claude-code/hooks/lib/nl-paths.sh"
  local ny_main_root=""
  [[ -f "$ny_nlpaths" ]] && ny_main_root=$(bash -c "source '$ny_nlpaths'; nl_main_checkout_root" 2>/dev/null)
  [[ -n "$ny_main_root" ]] || ny_main_root="$repo_root"
  local ny_md="${ny_main_root}/NEEDS-YOU.md"
  local ny_state="${live_home}/state/needs-you/ledger.json"

  if [[ ! -f "$ny_state" ]]; then
    _warn "needs-you-headers" "needs-you ledger not found at ${ny_state} — E.6 not yet installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _warn "needs-you-headers" "jq not available — cannot check needs-you open-count"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local ny_open
  ny_open=$(jq '[.items[] | select(.section == "decision" and .state == "open")] | length' "$ny_state" 2>/dev/null || echo 0)
  [[ "${ny_open:-0}" -gt 0 ]] || { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  if [[ ! -f "$ny_md" ]]; then
    _red "needs-you-headers" "NEEDS-YOU.md missing at ${ny_md} despite ${ny_open} open decision item(s) — run: bash adapters/claude-code/scripts/needs-you.sh render"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local -a headers=(
    "## Awaiting your decision"
    "## Open questions"
    "## In flight (sessions + waves)"
    "## Recently decided for your §8 review"
  )
  local -a missing=()
  local h
  for h in "${headers[@]}"; do
    grep -qF "$h" "$ny_md" 2>/dev/null || missing+=("$h")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    _red "needs-you-headers" "NEEDS-YOU.md (${ny_md}) missing $(printf '%s' "${#missing[@]}") of 4 canonical header(s) despite ${ny_open} open decision item(s): $(IFS='|'; echo "${missing[*]}") — run: bash adapters/claude-code/scripts/needs-you.sh render"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

**RED fixture:** mktemp -d sandbox (`HARNESS_DOCTOR_HOME=$D/live`,
`NL_REPO_ROOT=$D/repo`). Write `$D/live/state/needs-you/ledger.json` =
`{"schema_version":1,"items":[{"id":"NY-1","section":"decision","state":"open"}]}`.
Write `$D/repo/NEEDS-YOU.md` with only 2 of the 4 canonical headers (e.g.
missing "## Open questions" and "## Recently decided for your §8
review"). Assert `[doctor] RED needs-you-headers` naming both missing
headers.

**GREEN fixture:** same ledger (1 open decision item), `NEEDS-YOU.md`
containing all 4 canonical headers verbatim. Assert no RED for this
check-id. Also cover the gate itself: ledger with 0 open decision items
and a `NEEDS-YOU.md` missing all 4 headers — still GREEN (gate not
triggered), proving this predicate does not fire when `ny_open==0`.

---

## Manifest note

These six functions are NEW `check_*` bodies inside `harness-doctor.sh`
itself (an orchestrator-only file per §O.0.1) — they are not separate
scripts, so no `manifest-amendments.md` entries are needed for them (the
doctor's own manifest entry already covers `harness-doctor.sh` as a
whole). `scripts/scheduled-task-health.sh` (the one owned file this task
ships) DOES get a manifest entry — see this task's
`manifest-amendments.md`.
