# Evidence: deterministic-process-gate-2026-07-30

All six tasks landed in commit 432ce27
(feat(deterministic-process): pre-push becomes the authoritative review
gate). Self-test counts and the manual end-to-end dispatcher verification
are recorded in the plan file's own Testing Strategy section and are not
repeated in full here; this file exists to satisfy close-plan.sh's
per-task evidence-block convention.

Task ID: 1
Built `adapters/claude-code/hooks/review-record-push-gate.sh`, wired into
`adapters/claude-code/git-hooks/pre-push` as stage 4, commit 432ce27.
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
commit 432ce27. Self-test: 10 passed, 0 failed on both bash interpreters,
covering substantive-reason acceptance, short/placeholder-reason rejection,
and --sha override writing a marker for the NAMED sha rather than current
HEAD. Its integration with the real push gate is proven by that gate's own
Scenario 14 (invokes the real script, not a stub).
Verdict: PASS

Task ID: 3
Demoted `adapters/claude-code/hooks/review-record-commit-gate.sh` to
advisory-only and removed the REVIEW_RECORD_GATE_OVERRIDE escape hatch,
commit 432ce27. Self-test: 59 passed, 0 failed on both bash interpreters
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
with an honest bypass-path enumeration, commit 432ce27. Verified via
`bash adapters/claude-code/scripts/manifest-check.sh` (GREEN, 151 entries,
0 warn) and regenerated `docs/harness-architecture.md` +
`adapters/claude-code/doctrine/INDEX.md` (both GREEN against a fresh
regen).
Verdict: PASS

Task ID: 5
Added `check_deterministic_process_proof` to
`adapters/claude-code/hooks/harness-doctor.sh`, commit 432ce27. Self-test:
155 passed, 1 failed on both bash interpreters (the deterministic-process-
proof-* scenarios themselves all PASS; the one unrelated failure,
orphaned-worktree-work-live-owned-green, was reproduced IDENTICALLY against
the unmodified `git show HEAD:...` version of the same file run in place,
proving it pre-existing and unrelated). `harness-doctor.sh --quick` against
the repo manifest (bypassing the pre-install live mirror) shows zero REDs
from the new check.
Verdict: PASS

Task ID: 6
Corrected `adapters/claude-code/doctrine/review-before-deploy.md` and
`-full.md`'s stale "commit gate IS the enforcement" claim with an
Amendment H section naming the push gate as authoritative, commit 432ce27.
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
(hcr-20260730-30797d1d), commit 432ce27.
