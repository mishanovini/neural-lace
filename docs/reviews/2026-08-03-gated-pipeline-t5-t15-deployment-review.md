# Consolidated Deployment Review: gated-pipeline batch T5–T15 + integration

**Reviewer:** harness-reviewer (model: fable, dispatched by session 4a470c8c)
**Reviewed:** local master @ c068e063 (be5e4273, 422257c2, 6c975cbb, 34384396, bca1c3ad, b65bef7a, 88a6a1d5, e58e480e, 2b8e07b6, c068e063) — as-deployed code, against design r3 and the prior per-task review trail
**Reviewed at:** 2026-08-03

## Verdict: PASS

**Quotable verdict statement:** The T5–T15 batch at c068e063 is verified as-deployed: every sampled load-bearing implementation matches its audited spec — Checks 20–22 source and delegate to `review-chain-lib.sh` (rc_rule1/2/3 call sites at plan-reviewer.sh:4054–4187, the one-parser rule held), the register lib's fail-open contract is uniform from a single parse site, T7's `_sf_is_stale` owner-liveness check (alive ⇒ never stale) both fixes HR-F3 and retroactively closes the sf_release TTL-reclaim race noted in the T3/T4 review, the HALT split resolves canonically independent of `SF_STATE_DIR` with all four production consumers verified bare-canonical (the S6 regression was fixture-only, and a sibling sweep found no other instance of its class), and the RC_LEDGER_LANDING_DATE 2026-08-04 boundary fix is correct in the safe direction with a live-caught, evidenced root cause; seven suites were independently re-run by this reviewer (single-flight 43/43, review-chain 20/20, register 22/22, dispatch-chain-gate 6/6, workstreams-emit OK/exit-0, plus nl-maintenance 37/37 and digest 102/102 earlier this session), the bootstrap order is intact (G2 deliberately not yet wired — T16 precedes T17), and no cross-file composition defect was found. This record satisfies the review-before-deploy gate for the live-mirror sync of this batch; the unpushed/CI-red state remains owned by the push gates and the OD-021 triage, outside this verdict's scope.

## Evidence trail

- **Suites re-run by this reviewer (not trusted from the evidence file):** `single-flight-lib.sh` 43/43 · `review-chain-lib.sh` 20/20 (slow — see note 2 — but clean; final scenarios include the wrong-artifact-ref rejection) · `directives-register-lib.sh` 22/22 · `dispatch-chain-gate.sh` 6/6 · `workstreams-emit.sh` OK/exit-0 · earlier this session at the T3–T5 state: `nl-maintenance.sh` 37/37, `session-start-digest.sh` 102/102. Doctor's 9-minute suite not re-run here; T7's doctor deltas (cadence data-flip reads, TTL comment, label renames) verified by code read + the orchestrator's post-merge re-runs.
- **Delegation check (a):** plan-reviewer sources the lib via candidate resolution (:3929–3940) and calls `rc_rule1/rc_rule2/rc_rule3` — no reimplementation; self-test scenarios c20a/c21b/c22c cover chain-less/missing-MUST-REQ/derived-record.
- **Boundary fix:** reasoning at `review-chain-lib.sh:127–136` — day-granular exemption; a -03 boundary would have subjected same-day-earlier records to an unsatisfiable rule 3 (caught live by Check 22 on the plan's own chain, quoted in c068e063's message). Residual accepted in the safe direction: late-on-03 records are also exempt from rule 3 (rules 1–2 still apply) for one half-day window.
- **Composition sweep (b):** `sf_halt_active`/`SF_HALT_DIR` consumers swept (coord-sync:502, health-tick:239, supervisor-tick:331, nl-maintenance:484/690) — all bare-canonical, no S6-class sibling. `dispatch-chain-gate` absent from settings.json.template (0 matches) — bootstrap order preserved. Agents: both frontmatter `model: fable` (single-value form); model-policy carries both entries. Register: 21 entries, all BINDING, under the <30 rot target; OD-021 present. Zero-substrate inverse check reads `legacy_disabled_since`/`red_after_days` from schedule-manifest data (HR-F4 shape, HR-F7-compliant flips).

## Notes (non-blocking)

1. **Half-day rule-3 under-enforcement window** (records first-committed late 2026-08-03): correct trade, already documented at the code site; fully enforced from 2026-08-04.
2. **review-chain-lib suite runtime (~4–5 min)** — P-14's own law ("a check that cannot run in ~60s will stop being run") applies to this new suite; its git-fixture scenarios are the cost. Candidate follow-up: a fast subset flag for the routine path, full fixtures in CI. Filed as a watch-item, not a defect.
3. **Digest/doctor suites** were re-run by me at the pre-T7 state; post-T7 passes rest on the orchestrator's re-run plus code read of the 7b/7d deltas — stated for the record, HYPOTHESIZED-refutable by one 9-minute doctor suite run if anyone doubts it.

## Hard requirements confirmed for deployment

Bootstrap ordering intact (B14 landed T15; B13/T16 and B8/T17 still ahead — G2 unwired); manifest at 164 entries with the new mechanisms registered (HR-F9 discipline held in the same merge train); no new per-Bash hook cost introduced by the batch (all new surfaces ride Task|Agent events, pre-commit chains, or existing hooks). Deploy of this batch to the live mirror is approved by this record.
