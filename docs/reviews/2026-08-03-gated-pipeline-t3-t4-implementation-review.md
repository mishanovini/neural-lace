# Harness Review: Phase-A critical-fix implementations (T3/HR-F1, T4/HR-F2+F5+F8)

**Reviewer:** harness-reviewer (model: fable, dispatched by session 4a470c8c)
**Reviewed:** commits 6f5d1b22 + d46beee5 (merged) @ 19976fa2, against my original required-fix text (docs/reviews/2026-08-03-stage0-stage1-harness-review.md F1, F2/F5/F8) and design r3 REQ-A1/REQ-A2
**Reviewed at:** 2026-08-03

## Verdict: PASS

## Evidence trail (independent — builder and orchestrator claims were re-verified, not trusted)

- Full read of the changed code at HEAD: `single-flight-lib.sh` (header "THE RUN-TO-EXIT ASSUMPTION" + THE RULE, `sf_release` :312 with ownership guard), `nl-maintenance.sh` (`run_daemon` per-pass release with rationale comment; `_nm_pid_cmdline` with `/proc` → `ps -fp` fallback and the fail-closed unknown-identity contract; watchdog verified-kill/log-and-skip paths; S11 `SF_DISABLE=0` at the invocation with the required-not-optional comment), `harness-doctor.sh` (`_doctor_serve_cache_or_skip`; fingerprint + hooks-newest-mtime + dirty bit; doctor self-test 9c asserting exit 3 + SKIPPED), `session-start-digest.sh` (`refresh_doctor_cache` invoke-and-read-only with both env flags; S23 scenario), `install.sh:2019-2028` (exit-3 tolerated as "not an install failure").
- **Self-tests re-run by this reviewer:** `single-flight-lib.sh --self-test` → **34/34** · `nl-maintenance.sh --self-test` → **37/37** (includes S11 under the REAL guard and the T5/REQ-A3 end-to-end scenario) · `session-start-digest.sh --self-test` → **102/102**, S23a–e all PASS including S23e's byte-identical single-writer assertion.
- Grep-proof re-executed: zero cache-write sites remain in the digest (`rc=1` on the write-pattern grep); both `DOCTOR_VERDICT_CACHE_DISABLE` flags present in both files.
- Evidence file trail verified: the orchestrator-caught S11 re-masking defect (rewritten test still under inherited `SF_DISABLE=1` — the exact Q4 class my original review named) was sent back and fixed with RED/GREEN through the discriminating test itself (sf_release stubbed → 29/31 with the original 1-heartbeat symptom; restored → green). Comprehension audit PASS with independently spot-checked citations.

## Required-fix clause verification

**HR-F1 (T3, 6f5d1b22):**
- (a) daemon clears recursion var + releases lock each pass — **implemented substantively**: `sf_release` added with ownership safety (S15c/S16), `run_daemon` releases after every tick with the resident-loop rationale in place; the lib header states the run-to-exit assumption and THE RULE for future call sites (my required generalization, verbatim in spirit).
- (b) watchdog kills the daemon.pid process before relaunch — **implemented stronger than my original text**: cmdline identity verification (REQ-A1's M-8 hardening), fail-closed on unknown identity ("never kill on unknown"), log-and-skip on mismatch, plain SIGTERM, self-test stub before any real signal. D-11 compliant: bounded-harm reasoning is documented at the kill site.
- (c) S11 unmasked asserting ≥2 real ticks — **implemented**: `SF_DISABLE=0` explicit at the invocation (the inheritance trap that defeated the first submission is now named in a comment), asserts 3 distinct heartbeat epochs AND zero recursion-skips; mask at the old :790-791 gone.

**HR-F2+F5+F8 (T4, d46beee5):**
- F2(a)/F8: sf-skip serves the cached verdict **with faithful cached exit code** (a cached FAILED serves exit 1 — the exit-code-fidelity concern is clean) or exits distinct code 3 with the parseable SKIPPED line; doctor self-test 9c covers the empty-cache branch.
- F2(b): resolved in the **stronger single-writer form** — the digest never writes the cache at all; it reads back the doctor's own 5-field record. Corruption modes 1–3 of my F2 are impossible by construction, and S23e proves the property at runtime.
- F2(c): refresher invokes with `SF_DISABLE=1 DOCTOR_VERDICT_CACHE_DISABLE=1` — verified in code.
- F5: fingerprint gains live-hooks newest-mtime (portable scan) + working-tree dirty bit — matches my required fix verbatim.
- Consumer sweep: install.sh's `--verify` tolerates exit 3 explicitly.

## Notes (no blocking findings; all Minor)

1. **Staged-edit fingerprint residual** — the dirty bit is unstaged-only (`git diff`, not `--cached`), exactly as my own F5 fix text prescribed; a staged-but-uncommitted hook edit can still serve stale for up to the TTL. My original text's gap, now named; transient states, TTL-bounded. Candidate one-liner for a future sweep (`git diff --quiet && git diff --cached --quiet`).
2. **sf_release vs TTL-reclaim race** — if a tick ever exceeded the 120s lock TTL, another process could reclaim the lock and this daemon's subsequent `sf_release` would remove the reclaimer's lock (the ownership guard covers never-acquired, not reclaimed-after-acquire). Theoretical today (tick bodies run in seconds) and closed for real by T7's HR-F3 pid-liveness fix in this same plan — verify T7 lands before activation.
3. **Residual bare-exit-0 skip paths** (NL-FINDING-040 reentry guard, SESSIONSTART-SINGLEFLIGHT-01) — the out-of-scope call is **acceptable** against my F8 generalization: that sweep targeted `sf_guard` entry points' callers, and the `sf_guard` site is fixed; neither residual path is an sf_guard site; the one PROVEN consumer casualty (the refresher) is now immune to all three paths because it reads the cache back instead of trusting exit codes; the residual is named in the commit message and persisted (backlog + intake). The class stays open as a follow-up — correctly, as a filed item rather than silent scope creep.

## Hard-stop status (master handoff §0: "no NL-Maintenance registration until F1+F2 fixed AND re-reviewed")

- **HR-F1: fixed AND re-reviewed — YES.** Fix verified by code trace; discriminating test runs under the real guard; RED/GREEN recorded; self-tests independently re-run by this reviewer (34/34, 37/37).
- **HR-F2 (with F5/F8 at the doctor-quick site): fixed AND re-reviewed — YES.** Single-writer form verified by trace + grep-proof + S23a–e (102/102, re-run by this reviewer).
- **The hard stop is MET.** This record satisfies the re-review leg of T10's registration-ask precondition (fidelity F-3). Registration itself remains gated on operator ratification per DEC-4 — that gate is untouched and correct. Recommended before activation, not blocking this verdict: land T7 (HR-F3 pid-liveness + TTL sizing) first, since the daemon's steady-state runs under the exact lock whose reclaim semantics T7 hardens.

## Summary for the orchestrator

Both implementations satisfy every clause of the original required-fix text, twice exceeding it (identity-verified kill; single-writer-by-construction instead of schema-contract-by-discipline). The batch also demonstrates the process working as designed: the orchestrator caught the S11 re-masking regression pre-merge — the same masking class that hid HR-F1 originally — and the fix was proven RED/GREEN through the test that previously couldn't fail. T10's ask may now cite this record; sequence T7 before any live registration.
