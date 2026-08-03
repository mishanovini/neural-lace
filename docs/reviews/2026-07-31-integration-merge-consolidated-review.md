# Consolidated Post-Merge Review — Integration Merge 301e35f (+ f46017c, 1b41f31)

Operator-demanded separate-agent review ("if you are doing this surgically, we need
to make sure to run a thorough review by a separate agent afterward") of the
2026-07-31 takeover integration merge. Run as a 9-agent workflow: 8 independent
per-unit fidelity reviewers (blind to the merging session's claims, re-deriving
from the repo) + 1 synthesis agent that independently re-verified every DEFECT
finding before rendering the verdict. ~797k subagent tokens, 249 tool uses.

**Scope:** commits `301e35f` (11-conflict hand-merge of
`origin/wip/harness-hardening-2026-07-29` into master), `f46017c`
(grandfather-manifest regen at the merged tip), `1b41f31` (PL4e fixture adaptation).
Parents: `cc8ce41` (^1, pre-merge master) / `f408c11` (^2, wip tip).

## Verdict: FAIL (two PROVEN Majors) → remediated same session

## Per-unit verdicts

| Unit | Reviewer verdict | Synthesis disposition |
|---|---|---|
| admission-lib.sh | CLEAN | CLEAN (2 Minor advisories) |
| workstreams-emit.sh | DEFECT | Minors only — reclassified clean-with-advisories |
| close-plan.sh | CLEAN | CLEAN (1 Minor advisory) |
| spawn-worktree.sh | DEFECT | **Major PROVEN — survived re-verification** |
| needs-you.sh + perf-tick-snapshot.sh | DEFECT | Minor only — advisory |
| docs union (backlog / operator-todo / plan / evidence) | DEFECT | **Major PROVEN — survived re-verification** |
| grandfather-manifest.json @ f46017c | CLEAN | CLEAN |
| whole-changeset hygiene + suite evidence | CLEAN | CLEAN (3 Minor advisories) |

Universal checks corroborated across units: zero conflict markers in all 445
changed files, `bash -n` clean on all 182 shell files, no duplicated splice
blocks, all suite scenario sets strict supersets of both parents, manifest regen
byte-identical to a fresh tool run modulo `generated_at`, `1b41f31` proven
fixture-only.

## The two Majors (both PROVEN, both remediated)

**F1 — docs/operator-todo.md: merge flipped 4 pending operator decisions `[ ]`→`[x]`, burying them.**
^2 had 4 unchecked rows (`NY-1785425479-0d4d`, `NY-1785461708-830f`,
`NY-1785468126-b004`, `NY-1785468489-b4eb`); the merge carried them checked,
contradicting `docs/DECISIONS.md:73` and the takeover brief §6, with none of the
ids in this machine's ledger — genuinely pending decisions read as resolved.
**Root cause found during remediation:** a plain checkbox restore was reverted
within seconds by the cockpit auditor's `autoCheckOperatorTodo`
(`neural-lace/workstreams-ui/server/auditor.js:442`), which auto-checks any
unchecked AUTO row whose NY- id is absent from this machine's NEEDS-YOU open set —
the same mechanism that produced the flip during conflict resolution. **Root fix
(commit `0b26ff0`):** the four genuinely-open asks were re-homed into this
machine's ledger via the sanctioned `needs-you.sh add` path (id map in the commit
message and in each entry's provenance note; original ids could not be preserved —
filed as harness gap "cross-machine ask-migration primitive" in the machine-wide
nl-issues ledger). Stale rows deleted; DECISIONS.md 069 re-pointed.

**F2 — spawn-worktree.sh:264-279: de-registration splice still brace-group `{ ... } || true`.**
The round-3 M1 subshell sweep converted its two siblings but missed this third
splice; a set -u abort inside the sourced lib would escape the brace group and
report a COMPLETED removal as failed. **Fixed (commit `11c8006`):** converted to
the sibling subshell idiom with the sweep comment; self-test PASS including the
de-registration scenarios.

## Advisories (Minor, non-blocking)

Two fixed in `11c8006` (restored the admission splice's lost "SUBSHELL, not brace
group" rationale comment in workstreams-emit.sh; repointed needs-you.sh:1046's
dangling T34c→T38c cross-reference). The remaining six are persisted as backlog
row `POST-MERGE-REVIEW-ADVISORIES-20260731-01` (docs/backlog.md): committed
runtime session-state files, emit mode bit 100644, close-plan S30 `D22` variable
reuse, admission-lib:1660 dead `rc=$?`, suite-baseline correction (merged-tree
oracle numbers: admission-lib 31 scenarios/80 assertions, needs-you 61/0,
perf-tick 28/0, emit 123/123, close-plan 30 scenarios, janitor 22/22, brief
34/34 — never re-propagate the stale "67/53" briefing numbers), and the four
inherent `{ source lib; } || true` guards at emit :84/:90/:92/:142 (cannot be
subshelled; recorded so nobody re-finds them).

## Suite evidence

Full serial oracle run (post-merge tree): admission-lib, close-plan, needs-you,
perf-tick, spawn-worktree, estate-janitor, estate-brief all exit=0;
workstreams-emit first ran 122/123 (PL4e — a fixture written against the
pre-attribution contract; adapted in `1b41f31`, mirroring the other machine's own
PL4d adaptation), then 123/123. Independent re-runs during review confirmed
needs-you 61/0 and perf-tick 28/0 on the committed tree; spawn-worktree re-ran
SELFTEST PASS after F2.

## Remediation verification — ADDENDUM (verdict: REMEDIATION: PASS)

A separate read-only verification agent (research type, Opus, 2026-08-01
04:10–04:26Z) re-checked F1/F2 remediation end-to-end. All five checks PASS:

- **F2**: de-registration splice subshell-contained; zero brace-group splices
  remain (the two remaining `} || true` strings are comment prose quoting the
  old idiom); `bash -n` clean; SELFTEST PASS incl. de-registration scenarios.
- **F1 chain**: 4 OPEN ledger entries with correct one-to-one provenance to the
  Mac-mini originals; all 4 new ids on NEEDS-YOU.md meta lines (the parser's
  strict `DECISION_META_RE` anchoring means prose mentions of the OLD ids
  cannot widen the open set — a trap a loose regex would have hit); 4 unchecked
  todo rows, 0 old ids; DECISIONS.md 069 lineage correct.
- **Mechanism proof**: auditor.js:1190 + :449 compose into "an id in the open
  set can never be auto-checked" — the fix disarms the exact revert mechanism.
- **Stability**: rows unchanged across a 16m24s watched window in which the
  live auditor (PID 68980, 120s cadence) demonstrably advanced cycles 99→100
  and fired NO auto-check heal event after the re-home (last one remains the
  03:29:12Z count:4 event that ate the first fix attempt).

Two residual notes, recorded honestly:
1. *(closed after the addendum)* The verifier could not prove the spawn-worktree
   PASS log was produced by the post-fix blob (no SUT fingerprint in the log;
   ordering evidence only). Closed by re-running `--self-test` on the committed
   tree (working tree clean at HEAD `0b26ff0` for that file, blob-sha verified
   before the run) — result recorded in the record's findings summary.
2. **Minor record-accuracy defect (permanent record, non-functional):** commit
   `11c8006`'s message claims "docs/operator-todo.md … Restored to [ ]" but its
   diff does not contain that file — the cockpit auditor had already re-flipped
   the rows 11 minutes before the commit (heal event 03:29:12Z), so nothing
   remained to stage. The true story is in `0b26ff0`'s message; this note is
   the correction the verifier asked to be filed with the review.

---
*Workflow run `wf_42691992-57c`; per-agent transcripts under the session's
subagents/workflows directory. Original 9-agent report reproduced in full above;
remediation commits: `1b41f31`, `11c8006`, `0b26ff0`.*
