# review-chain fixtures (gated-pipeline-master-2026-08 Task 1)

Fixtures for `hooks/lib/review-chain-lib.sh` and `hooks/dispatch-chain-gate.sh
--check`. `review-chain-lib.sh --self-test` builds its OWN throwaway git repo
for the eight design-r3/REQ-B6 rule scenarios (nothing here is read by that
self-test) — the files in this directory back the GATE's own `--self-test`
and its `--check` demo commands (plan Task 1 "Prove it works" steps 2-3),
which run against this real, committed repo history.

- `chainless-plan.md` — no `## Review Chain` section. `--check` must BLOCK
  with a complete {WHAT/WHY/FIX/ESCAPE} message.
- `valid-chain-design.md` + `valid-chain-plan.md` — a design + the plan that
  reviews it, with a fully valid Review Chain block. `--check` must exit 0.
- `design-review-record.md` / `plan-review-record.md` — the two review
  records the valid chain cites; each `**Reviewed:** <path> @ <blob>` header
  attests the real committed blob (design: raw `git hash-object`; plan:
  CANONICALIZED — chain + in-flight sections excluded, `rc_blob_of ... plan`).
- `dispatch-ledger.jsonl` — the fixture dispatch ledger the valid chain's rule
  3 cross-checks against.

**Dispatch-ledger row schema (the shared contract with Task 15 — REQ-B14):**
`workstreams-emit.sh`'s `--on-builder-complete` writer and
`review-chain-lib.sh`'s rule-3 reader must agree on exactly this shape:

```
{"subagent_type": "<reviewer agent name>", "model": "<model id>", "ts": <unix epoch, number>, "session_id": "<string>", "artifact_ref": "<path the reviewer reviewed, or empty string for the degraded type-only match>"}
```

**Why two commits, not one:** `valid-chain-plan.md`/`valid-chain-design.md`
were committed first (6bff352d), and the two records + the ledger fixture in
a follow-up commit (942b156f) — so rule 3's window
`[artifact's first commit, record's HEAD commit time]` is a real, two-point
range rather than a single instant (both artifact and record would otherwise
land in the exact same commit and collapse the window). The ledger rows' `ts`
values are the second commit's epoch, `1785751212` — the record's own commit
time, satisfying both bounds.
