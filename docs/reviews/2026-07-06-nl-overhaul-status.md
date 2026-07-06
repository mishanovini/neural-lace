# NL Overhaul — program status snapshot (2026-07-06)

Oracle: checkbox state of `docs/plans/nl-overhaul-program-2026-07.md` @ master 76cdf8d
(every `[x]` below was flipped by task-verifier after independent verification — no
self-reports), plus the live doctor (`GREEN — 19 checks`, 1 honest WARN) and the
in-flight workflow registry. Companion docs: ADR 058 (architecture), ADR 059
(session-end redesign), specs-b/c/d/e/f, evidence file (same directory as the plan).

## Done — verified and live

| Wave | Tasks | State |
|---|---|---|
| A (prep) | — | done (pre-wave estate triage, 2026-07-02) |
| B — truth reconciliation | B.0–B.12 (13/13) | ✅ doctor built, install completeness, baseline snapshot, estate freeze |
| C — context diet | C.0–C.6 (7/7) | ✅ always-loaded 883,882B → ~9.8KB (−99%); constitution live; JIT doctrine |
| D — gate consolidation | D.0–D.6 (7/7) | ✅ Stop 22→6, SessionStart 24→8, blocking units 10/12; cutover verified |
| E — signals/continuity | E.0–E.12 except E.7 (12/13) | ✅ digest, sandbox sweep, waiver-density, synthetic runner, KPIs, NEEDS-YOU, nl-issue, pre-compaction, incentive pins, batched Stop verdict (ADR 059), end-manifest; §E.W live cutover (Stop 6→4) verified doctor-full GREEN |
| F — governance/closure | F.5 (audit+demotion+remedy-chain+Circuit guard) | ✅ flipped after adversarial verification |
| F.3 substance | estate dispositions | ✅ executed + operator-approved 2026-07-06 (checkbox awaits task-verifier) |

Also live beyond the plan's letter: functional-link warn (F.L, operator directive),
.gitattributes CRLF guard (NL-FINDING-038), estate sweep (26 worktrees / 115 branches,
zero content lost), 19-check doctor GREEN.

## Remaining

| # | Item | Owner | State |
|---|---|---|---|
| 1 | F.1 / F.2 / F.6 verification gaps (doctor-predicate fold, worktree-age fixture, root-dedup FP, best-practices.md, sync-lock semantics) | fix workflow `wbxmvh5yb` | **in flight now** → re-verify → flip |
| 2 | F.3 checkbox flip | task-verifier | ready (substance done) |
| 3 | Synthetic-runner CI companion plan (workflow yml + live green Actions run) — 3 build tasks + closure | next builder dispatch | queued |
| 4 | E.7: register NL-session-resumer schtasks + live kill-drill + flip | orchestrator (me) | deliberately deferred until estate cleanup (dead transcripts age out) |
| 5 | Closure Contract: all-tasks sweep, temp-HOME install battery, CI greens, estate reconcile, completion report | orchestrator | after 1–4 |
| 6 | F.4 retro: §F.4-PROTOCOL pre-registered queries vs baseline + ADR 058 refutation check + observability-program activation proposal | strongest model + operator | **window-gated by design: ~2026-07-24** (refutation criteria measure 3 weeks post-D-cutover) |

## Shape of the end

Build-complete (items 1–5) is days away and operator-free except reading reports.
Program closure = F.4 (item 6), intentionally scheduled at the 3-week measurement
window so the retro grades real usage data, not fresh paint. At F.4 the operator
gets: the before/after table for all six baseline metrics, the refutation verdict,
and the one-word activation call for the observability program (DRAFT, already
build-committed).
