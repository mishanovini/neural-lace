# E.10 manifest amendments (for the §E.W orchestrator merge)

Per specs-e §E.0.1 rule 2, the E.10 builder does not edit
`adapters/claude-code/manifest.json` directly. This fragment lists the
`honest_status` corrections this task's work makes true, for the
orchestrator to fold in at §E.W integration.

## 1. `workstreams-emitters` entry — heartbeat mode now scheduled (NL-FINDING-022 WIRE)

Current entry (`adapters/claude-code/manifest.json`, id `workstreams-emitters`):

```json
"honest_status": "workstreams-emit.sh wired directly (SessionStart + spawn PreToolUse); Stop-side members dispatched via workstreams-stop-writer.sh since D.5."
```

This claim was already accurate and is NOT contradicted by this task's
work (it describes template-wired invocation modes, not the
`--heartbeat` mode, which is a scheduled-task trigger, not a
settings.json wiring). No correction is REQUIRED for schema validity.

Recommended amendment (optional, for completeness — not a correctness
fix): append a clause naming the heartbeat's new trigger mechanism so a
future reader does not have to cross-reference this task's commit:

```json
"honest_status": "workstreams-emit.sh wired directly (SessionStart + spawn PreToolUse); Stop-side members dispatched via workstreams-stop-writer.sh since D.5. --heartbeat mode is registered as the Windows scheduled task NL-workstreams-heartbeat by install.sh (every 5 min) — NL-FINDING-022 WIRE decision, specs-e §E.10 item 6; harness-doctor.sh's check_heartbeat_task predicate verifies task existence and WARNs (not RED) when unregistered."
```

## 2. No new manifest entries required from this task

E.10 added no new standalone hooks/scripts that need their own manifest
entry (it edited existing hooks: `work-integrity-gate.sh`,
`session-honesty-gate.sh`, `harness-doctor.sh`, `install.sh`,
`workstreams-state-gate.sh`, `workstreams-stop-gate.sh`,
`teammate-spawn-validator.sh`, `workstreams-task-binding.sh`,
`bug-persistence-gate.sh`, `scope-enforcement-gate.sh`, plus added a new
shared library `hooks/lib/waiver-purpose-clause.sh` — libraries are not
independently manifest-entried per the existing convention, since
`hooks/lib/` is synced as a unit by install.sh and covered by
`check_lib_deps`).

## 3. `blocking-budget-check.js` — no change to the 12-unit count

This task's edits (marker pass-through, resolution-aware DONE-vs-block,
pin-f purpose-clause validation, spawn-race bounded re-read, untracked-
dirt exclusion, discovery-exemption) modify BEHAVIOR inside existing
manifest-registered units (bug-persistence, work-integrity,
session-honesty, agent-teams via teammate-spawn-validator.sh, spec-freeze
via scope-enforcement-gate.sh) — none of them add or remove a blocking
unit. The ADR 058 D5 "blocking gates ≤ 12" budget is unaffected;
`blocking-budget-check.js` should still report 12/12 after this task's
commits (not independently re-run by this builder — the orchestrator's
§E.W step 5 install + doctor pass is the point this gets re-verified
against the merged tree).

## 4. New doctor checks added (documented for the orchestrator's awareness, not a manifest change)

`harness-doctor.sh` (this task, item 12 + item 4 + item 6 + item 9 + item
2) gained five new check functions, wired into `run_quick_checks`:
`check_manifest_freshness`, `check_wave_e_surfaces` (E.1/E.7/E.8/E.9
predicates implemented verbatim per their fragments; E.5/E.6 explicitly
SKIPPED — see §E.10 item 12 note in the doctor's own comment header),
`check_heartbeat_task`, `check_untracked_dirt_ignore_rule`,
`check_pin_f_waiver_purpose_clauses`. These are doctor-internal additions
(no manifest entry required — `harness-doctor.sh` itself is already a
single manifest entry, id `harness-doctor`, kind `surfacer`; its internal
check count is not manifest-tracked).
