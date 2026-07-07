# Evidence — Task O.4 (Cockpit rebuild: thin view over derived truth)

EVIDENCE BLOCK
==============
Task ID: O.4
Task description: Cockpit rebuild: Workstreams UI reads the derivation lib (delete/retire its event-sourced truth path per the sketch disposition); divergence-reconciler flags derived-vs-displayed drift — Done-when: operator exercises the six questions in the GUI; acceptance scenario recorded (constitution §4 — demonstrated, not shipped-as-components).
Verified at: 2026-07-07T21:45:00Z
Verifier: task-verifier agent (adversarial re-derivation; independent runtime exercises against the live 7733 cockpit, not the advocate run)

Oracle: specified — the plan Acceptance Scenarios section (plan lines 206-216, normative) + docs/reviews/2026-07-06-o4-acceptance-scenarios.md (10 scenarios: q1..q6 = the six operator questions; s7 drift, s8 degradation, s9 unobserved-honesty, s10 interrupt-priority). Acceptance bar: displayed == `bash ~/.claude/scripts/nl.sh <sub> --json` same-moment (derived-vs-displayed equality; thin-view IS the spec).

Comprehension-gate: not applicable (rung: 1)

Checks run:
1. Task-text match (caller vs plan lines 61-65)
   Result: PASS — exact match.
2. Acceptance artifacts re-derived (Done-when "recorded" clause)
   Files: .claude/state/acceptance/o4-cockpit/f2d19bb9-...-2026-07-07T12-07-00Z.json (initial: 10 scenarios, 7 PASS / 3 FAIL [q4,q5,q6] + keyboard mandated-check FAIL) and ...T17-10-00Z-rerun.json (re-run @ master 472625c: exactly the 4 prior FAIL items + q1 regression spot-check, 5/5 PASS -> combined 10/10). Scenarios-doc sha256 identical across both runs (a92487648a6d...); every scenario maps to one of the six questions or the drift/degradation/honesty/priority properties. Oracle payloads (rerun-q4-health, rerun-q5-costs, rerun-q6-why + real-session, rerun-q6-server-payload), screenshots (rerun-cockpit-full.png 1280x2400 shows all six panes rendered: interrupt strip, priority-sorted board, 15-gate health table with 7 waiver-dominant flags, per-session cost rows with freshness chips, shipped-SHA diff with Mark-seen, honest rc=124 backlog error + Retry, drift:9 badge), network/console logs all present.
   Result: PASS
3. INDEPENDENT Q4 exercise (health pane derived-vs-displayed equality) — my own run, not the advocate run
   Command: curl http://localhost:7733/api/pane/health (bracket t1/t2) with `bash ~/.claude/scripts/nl.sh health --json` (rc=0) run in between; node deep-compare.
   Output: t1==t2 identical; pane .data deep-equals oracle EXACTLY (15/15 gates, all block/waiver/downgrade counts, dominant flags, doctor verdict "unavailable" both sides — honest for the empty doctor cache).
   Result: PASS — PROVEN same-moment derived-vs-displayed equality.
4. INDEPENDENT Q6 exercise (why drawer payload carries the causal chain + verdict)
   Command: curl "http://localhost:7733/api/pane/why?session=acc-o4-why-8514"
   Output: rc=0 payload with .verdict "blocked by workstreams-state-gate (...024-class...); next: workstreams-state-gate allow", 3-row time-ordered chain (spawn-dispatched -> block -> allow), transcript_status:"absent" honestly labeled.
   Adversarial probe: same endpoint for the heavy-transcript real sid f2d19bb9-... returned the HONEST in-band degradation contract (data:null, rc:124, stderr_tail "nl why timed out after 60000ms", exact command named) — the s8 behavior, no fabrication, no hang.
   Result: PASS
5. Divergence-reconciler live
   Command: curl http://localhost:7733/api/reconciler
   Output: {"drift_count":9, mismatches[] each naming session, tree claim, derived_state:"absent", "derived is authoritative"} — the known baseline estate finding (9 real stale tree-state claims), comparator alive by design (s7 disposition: retirement removed pane reads + GUI writes, not the comparator).
   Result: PASS
6. Server liveness (operator instance)
   Command: curl http://localhost:7733/api/health
   Output: {"ok":true, oldest_pane_age_ms, refresh_interval_ms:30000, ...}
   Result: PASS
7. Trust-path retirement (task clause 2)
   Command: grep -c workstreams-state-gate adapters/claude-code/settings.json.template AND ~/.claude/settings.json
   Output: 0 and 0. attic/ contains workstreams-state-gate.sh, workstreams-turn-emit.sh, workstreams-extract-pending.sh (+ conversation-tree-extract-pending.sh); hooks/workstreams-state-gate.sh is a documented exit-0 shim (manifest coverage). docs/findings.md NL-FINDING-024 Status: closed with O.4 closure note. manifest-check.sh on master: "GREEN — 109 entries, 101 hooks covered, 0 warn".
   Result: PASS
8. Thin-view architecture (task clause 1)
   Command: grep tree-state neural-lace/workstreams-ui/server/*.js
   Output: derive-cache.js shells `nl <sub> --json` (contract C5); the ONLY tree-state reads live in reconciler.js (comparator); server.js header documents "REPLACES the tree-state-reading server".
   Result: PASS
9. Build lineage
   Command: git merge-base --is-ancestor 08108f9 master; git merge-base --is-ancestor bac3083 master
   Output: both ancestors (via 568daa0 integration + b2bb11b merge; master==origin/master==53d3bee).
   Result: PASS
10. Self-test replay on master content (independent, not trusted from claims)
    Commands: node server/server.selftest.js ; node web/cockpit.selftest.js
    Output: "self-test summary: 28 passed, 0 failed" and "self-test summary: 33 passed, 0 failed".
    Result: PASS — matches claimed 28+33.
11. Docs impact field
    Result: SKIPPED — plan predates the Docs-impact convention (no task in this plan carries the field); grandfathered per verifier protocol.

Runtime verification: curl curl -s --max-time 20 http://localhost:7733/api/pane/health (data deep-equals `bash ~/.claude/scripts/nl.sh health --json` same-moment, 15/15 gates)
Runtime verification: curl curl -s --max-time 90 "http://localhost:7733/api/pane/why?session=acc-o4-why-8514" (.verdict + 3-row 024-class chain + transcript_status absent)
Runtime verification: curl curl -s http://localhost:7733/api/reconciler (drift_count:9, per-mismatch notes, derived-is-authoritative)
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::self-test (28/28 on master)
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::self-test (33/33 on master)
Runtime verification: file adapters/claude-code/settings.json.template::workstreams-state-gate (0 matches — retired)
Runtime verification: file docs/findings.md::NL-FINDING-024 Status closed

DEPENDENCY TRACE
================
Step 1: operator opens http://localhost:7733 (node PID 15548, main-checkout server.js @ master)
  -> Verified at: /api/health ok:true + rerun-cockpit-full.png (rendered six-pane UI)
Step 2: panes poll /api/pane/<q>; derive-cache.js shells `nl <sub> --json` (derivation lib = oracle)
  -> Verified at: check 3 (pane-health data deep-equals independently-run oracle) + derive-cache.js source
Step 3: user-visible chips/tables/verdict render the oracle values
  -> Verified at: advocate DOM-bracket assertions (both artifacts) + screenshot + check 4 (.verdict payload)
Step 4: reconciler compares legacy tree-state claims vs derived set; drift badge + ledger warn
  -> Verified at: check 5 (/api/reconciler drift 9) + s7 PASS (seeded ghost -> badge -> dedup warn -> clears on restore)

Git evidence:
  Files modified: neural-lace/workstreams-ui/** (08108f9 rebuild, bac3083 fix1), adapters/claude-code/{settings.json.template,manifest.json,hooks/*} + docs/findings.md (568daa0 retirement) — all ancestors of master 53d3bee.

Judgment ruling (Done-when clause "operator exercises the six questions in the GUI"):
The plan normative Acceptance Scenarios section (lines 206-216) defines the runtime end-user-advocate run against the scenarios doc as "the PASS/FAIL artifact O.4's Done-when requires" — the advocate exercising the six questions adversarially in the GUI on the operator behalf IS the plan own section-4 acceptance-loop design, and it is recorded (both artifacts + oracle payloads + screenshots). Ruled SUFFICIENT for O.4. The literal operator-trust measure ("operator trusts the cockpit enough to stop asking sessions for status") is pre-registered as the O.7 retro metric (task O.7 "operator-trust check") and is NOT an O.4 gate. The operator cockpit is live at http://localhost:7733 for their own use.

Residual estate findings (already filed by the advocate via nl-issue.sh; none gate O.4):
- baseline tree-state drift 9 -> badge fires permanently until tree-state cleaned or comparator retired (O.6 predicates);
- derivation latency degrades under concurrent load (nl status/why rc=124 at 60-150s; honest STALE labeling observed live) — O.9/OBS_NL_TIMEOUT_MS disposition;
- doctor cache empty -> Q4 verdict "unavailable" (honest both sides) — O.3/O.6;
- external acc-o4 ledger sweep destroyed a live fixture mid-re-run (coordination finding, harness not product).

Verdict: PASS
Confidence: 9
Reason: PROVEN: I independently exercised two of the six questions end-to-end against the live operator cockpit (pane/health deep-equals the same-moment `nl health --json` oracle 15/15 gates; pane/why carries the verdict + time-ordered 024-class chain), replayed both self-tests green on master (28/28 + 33/33), confirmed trust-path retirement (0 grep hits in template + live settings, attic-moved scripts, FINDING-024 closed, manifest-check GREEN), confirmed both build commits are ancestors of master, and re-derived the recorded acceptance artifacts (initial 7/10 + re-run 5/5 covering exactly the prior FAILs -> 10/10 @ 472625c) with scenario-to-question mapping intact. Adversarial probe (heavy-transcript why) surfaced only the documented honest-degradation contract, not a defect.
