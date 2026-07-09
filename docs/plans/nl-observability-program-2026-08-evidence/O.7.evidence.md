# Task O.7 — Retro vs pre-registered metrics

EVIDENCE BLOCK
==============
Task ID: O.7
Task description: Retro vs pre-registered metrics (sketch §success-metrics): time-to-answer drill Q1-Q6, zero unmapped event types, operator-trust check — Model: strongest available — Done-when: completion review doc with measured numbers.
Verified at: 2026-07-09T04:45:00Z
Verifier: task-verifier agent

Oracle: specified + derived — SPECIFIED: the Done-when ("completion review doc with measured numbers") and docs/reviews/2026-07-04-observability-design-sketch.md §"Pre-registered success metrics" (the three metrics the doc must cover). DERIVED (anti-fabrication): the two mechanical numbers RE-DERIVED independently against the live estate to confirm they are real, not asserted — ledger-observed event set vs consumer-map keys, and a live nl time-to-answer measurement.

Comprehension-gate: not applicable (rung: 1)

Checks run:
1. Deliverable exists on master f6203c4
   Command: git show origin/master:docs/reviews/wave-o-retro.md | head; wc -l
   Output: 137-line completion review doc present (force-added; docs/reviews is gitignored). Title "Wave O retro — NL Observability Program vs pre-registered success metrics"; authored orchestrator (Opus 4.8, strongest available), 2026-07-08.
   Result: PASS
2. Covers all three pre-registered metrics from the design sketch
   Command: git show origin/master:docs/reviews/2026-07-04-observability-design-sketch.md | grep -A40 "Pre-registered success metrics"
   Output: sketch metrics = (1) median time-to-answer Q1-Q6 <10s by drill; (2) zero ledger event types without a mapped consumer (doctor-audited); (3) operator trusts the cockpit enough to stop asking sessions. Retro has a dedicated ## section for each (Metric 1 / Metric 2 / Metric 3), each with measured numbers.
   Result: PASS
3. RE-DERIVE Metric 2 (zero unmapped event types) — the doc claims ∅ / 100% mapped / 27 mapped types
   Command: comm -23 <(tail -1000 ~/.claude/state/signal-ledger.jsonl | jq -r .event | sort -u) <(jq -r '.event_types|keys[]' ~/.claude/observability-consumer-map.json | sort -u)
   Output: EMPTY (no output; exit 0). Ledger last-1000 distinct events (11: bg-task-started, flush, reap, session-compact, session-start, session-stop, spawn-concluded, spawn-dispatched, stop-cycle, turn-trace, warn) are ALL a subset of the map's 27 event_types. jq '.event_types|keys|length' = 27 (matches doc's "maps 27 event types").
   Result: PASS — doc's "∅ (empty) / Metric 2 ACHIEVED" is REAL, not fabricated.
4. RE-DERIVE Metric 1 (time-to-answer <10s) — spot-check one claim (doc Q2 table = nl needs-me 0.45s)
   Command: time bash ~/.claude/scripts/nl.sh needs-me
   Output: real 0m0.399s (16 open items rendered, oracle: od_needs_me). Consistent with the doc's 0.45s claim and well under the 10s bar.
   Result: PASS — the doc's sub-10s time-to-answer table is REAL against the live estate, not fabricated.
5. Honesty of Metric 3 (operator-trust) — must be delivered-but-confirm-in-use, NOT self-certified
   Output: doc reads "DELIVERED as a trustworthy surface; trust-in-use is now the operator's to confirm. The honest test — does the operator consult the cockpit instead of asking sessions — can only be answered by the operator over the coming weeks; this retro cannot self-certify it." Grounds delivery in the 10/10 adversarial acceptance run (O.4) + the two mechanically-enforced design laws. No false self-certification.
   Result: PASS
6. Honesty of the O.3 cold-touch caveat (a report that reads better than reality is a defect)
   Output: Metric 1 records the caveat explicitly — "one non-reproducible 11.2s cold-OS-first-touch on nl costs ... a genuine first-touch-after-reboot may momentarily exceed [the bar]." The doc does NOT hide the single over-bar measurement; it reports it and bounds it (controlled cold-cache 9.6s, steady-state 6.5-7.0s).
   Result: PASS

Runtime verification: file docs/reviews/wave-o-retro.md::Metric 2: ACHIEVED  (deliverable on master f6203c4; covers all 3 pre-registered metrics with measured numbers)
Runtime verification: sql comm -23 <(tail -1000 ~/.claude/state/signal-ledger.jsonl | jq -r .event | sort -u) <(jq -r '.event_types|keys[]' ~/.claude/observability-consumer-map.json | sort -u)  (RE-DERIVED EMPTY — zero unmapped event types; confirms Metric 2 real)
Runtime verification: test nl.sh::needs-me  (time bash ~/.claude/scripts/nl.sh needs-me = 0.399s < 10s; confirms Metric 1 time-to-answer real)
Runtime verification: functionality-verifier O.7::SKIP (rationale: doc-only completion-review deliverable; no UI/API/AI/Data runtime surface — the oracle is re-derivable measured numbers, exercised directly by checks 3-4 above)

Git evidence:
  docs/reviews/wave-o-retro.md present on origin/master f6203c4 (force-added; docs/reviews gitignored, design sketch + this deliverable tracked).
  HEAD == origin/master == f6203c4a0367fb9f8102193e269cee93e8b69cee (branch tmp/o4-flip).

Verdict: PASS
Confidence: 9
Reason: PROVEN: docs/reviews/wave-o-retro.md exists on master f6203c4 as a 137-line completion review covering all three pre-registered success metrics from the design sketch with measured numbers. The two mechanical numbers were RE-DERIVED independently against the live estate and MATCH the doc: (Metric 2) comm -23 of ledger-observed events minus consumer-map keys = EMPTY (27 types mapped, zero unmapped) — the doc's "∅ / ACHIEVED" is real; (Metric 1) nl needs-me measured 0.399s vs the doc's 0.45s, well under 10s — the doc's time-to-answer table is real. The doc is HONEST on the qualitative third metric (operator-trust "DELIVERED as a trustworthy surface; trust-in-use is now the operator's to confirm" — explicitly does NOT self-certify) and records the O.3 cold-touch caveat (the single non-reproducible 11.2s first-touch is reported, not hidden). Done-when ("completion review doc with measured numbers") is satisfied: the doc exists, covers all three metrics, its numbers are re-derivable/real, and its caveats are honestly reported — the Done-when does not require every metric to be a perfect pass, only real measured numbers honestly reported.
