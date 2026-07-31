# Evidence: deterministic-process-gate-2026-07-30

All six tasks landed in commit 3a6e821
(feat(deterministic-process): pre-push becomes the authoritative review
gate). Self-test counts and the manual end-to-end dispatcher verification
are recorded in the plan file's own Testing Strategy section and are not
repeated in full here; this file exists to satisfy close-plan.sh's
per-task evidence-block convention.

> **FOLLOW-UP COMMIT, 2026-07-30.** A `harness-reviewer` pass on this landed
> work returned REJECT (3 Critical / 8 Major / 1 Minor) and the findings were
> closed in a follow-up commit. Per-task self-test counts below were accurate
> AT `3a6e821` and have since MOVED, because the follow-up added scenarios:
> push-gate 23/0 → **28/0**, commit-gate 59/0 → **60/0**, lib 40/0 → **43/0**,
> doctor → **166/3** (bash 3.2.57) / **168/1** (bash 5.3.15). Two counts in
> this file were never accurate at any commit and are corrected in place
> (marked CORRECTED). Notably, Task 3's claim below that "Scenario 8 proves
> REVIEW_RECORD_GATE_OVERRIDE is now inert with no differential effect" was
> TRUE as a statement but NOT PROVEN by that scenario, which asserted rc=0 on
> a gate that always exits 0 — mutation-proven vacuous in review. It now
> asserts a byte-for-byte stderr differential and kills the resurrection
> mutant.

Task ID: 1
Built `adapters/claude-code/hooks/review-record-push-gate.sh`, wired into
`adapters/claude-code/git-hooks/pre-push` as stage 4, commit 3a6e821.
Self-test: 23 passed, 0 failed on both /bin/bash 3.2.57 and
/opt/homebrew/bin/bash 5.3.15, including Scenario 15 (mutation-proof: a
neutered copy of the block decision wrongly allows the golden-case push,
proving the real rc=1 is load-bearing) and Scenario 13b (a well-formed but
nonexistent remote_sha still triggers a full-tree fallback scan rather than
a silent allow). Manually verified end-to-end through the REAL
`git-hooks/pre-push` dispatcher against a throwaway bare-remote fixture:
block -> authorize -> allow -> sha-scoped re-block on a second commit.
Verdict: PASS

Task ID: 2
Built `adapters/claude-code/scripts/authorize-review-record-push-override.sh`,
commit 3a6e821. Self-test: 10 passed, 0 failed on both bash interpreters,
covering substantive-reason acceptance, short/placeholder-reason rejection,
and --sha override writing a marker for the NAMED sha rather than current
HEAD. Its integration with the real push gate is proven by that gate's own
Scenario 14 (invokes the real script, not a stub).
Verdict: PASS

Task ID: 3
Demoted `adapters/claude-code/hooks/review-record-commit-gate.sh` to
advisory-only and removed the REVIEW_RECORD_GATE_OVERRIDE escape hatch,
commit 3a6e821. Self-test: 59 passed, 0 failed on both bash interpreters
(was 62/62 pre-demotion). Scenario 1b ("GOLDEN — REVIEW-GATE-UNSATISFIABLE-
FROM-BUILDER-01") proves a builder with no override set makes forward
progress at commit time; Scenario 8 proves REVIEW_RECORD_GATE_OVERRIDE is
now inert with no differential effect and nothing logged to the retired
audit log.
Verdict: PASS

Task ID: 4
Added `chokepoint`/`bypass_paths` fields to
`adapters/claude-code/manifest.json` and
`adapters/claude-code/schemas/manifest.schema.json`; flipped
review-record-commit-gate's blocking to false; added the two new entries
with an honest bypass-path enumeration, commit 3a6e821. Verified via
`bash adapters/claude-code/scripts/manifest-check.sh` (GREEN, **153** entries
— "151" as first recorded here was transcribed, not observed; corrected
2026-07-30) and regenerated `docs/harness-architecture.md` +
`adapters/claude-code/doctrine/INDEX.md` (both GREEN against a fresh
regen).
Verdict: PASS

Task ID: 5
Added `check_deterministic_process_proof` to
`adapters/claude-code/hooks/harness-doctor.sh`, commit 3a6e821. Self-test
figures CORRECTED 2026-07-30 (harness-reviewer follow-up): the "155 passed,
1 failed on both bash interpreters" recorded here reproduces on NEITHER
interpreter. Re-measured from command output: **166/3 on `/bin/bash` 3.2.57**
and **168/1 on `/opt/homebrew/bin/bash` 5.3.15** (pre-change baseline 158/3
and 160/1). The deterministic-process-proof-* scenarios all PASS on both.
The failures ARE pre-existing and reproduce identically against the
unmodified base: `orphaned-worktree-work-live-owned-green` on both
interpreters, plus the `o6-obs-scheduled-tasks-red` pair on bash 3.2.57 only.
ALSO CORRECTED: this entry cited commit `432ce27`, which is NOT in master's
history (a dangling object left by a rebase); the commit that actually landed
this work is `3a6e821`.
Verdict: PASS

Task ID: 6
Corrected `adapters/claude-code/doctrine/review-before-deploy.md` and
`-full.md`'s stale "commit gate IS the enforcement" claim with an
Amendment H section naming the push gate as authoritative, commit 3a6e821.
Verified by reading both files' current content; no automated check exists
for doctrine prose (Verification: mechanical — the fix IS the doc change).
Verdict: PASS

## Plan-level review record
Reviewed by harness-reviewer (opus) across three passes: round 1 REJECT (3
Critical/9 Major/5 Minor); round 2 REJECT (1 Critical/2 Major/3 Minor)
after fixes; round 3 REFORMULATE (one wrong review-queue.sh --status
value) after routing the remedy through review-queue.sh -> review-runner.sh.
All findings fixed. PASS recorded at
docs/reviews/records/2026-07-30-harness-change-review-30797d1d.json
(hcr-20260730-30797d1d), commit 3a6e821.
