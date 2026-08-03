# 065 — admission-lib.sh env-bypass closure: three closed, one accepted

**Date:** 2026-07-29
**Status:** DECIDED (builder decision, T6-PREREQUISITES (b) micro-slice)
**Scope:** `adapters/claude-code/hooks/lib/admission-lib.sh`

## Context

T6's acceptance criterion (b) (`docs/plans/accountable-estate-program-2026-07.md`,
task T6) requires the four environment bypasses named in admission-lib.sh's header
to be "closed or accepted in writing" before the enforcement flip. The 2026-07-28
review found the lib — sourced into every dispatcher's own shell — trusts four
environment variables unconditionally:

| Bypass | Effect if set |
|---|---|
| `ADM_ABSURD_SESSION_CAP` | Raises the ~50-session absurd-level backstop, admitting when derived occupancy says would-block |
| `ADM_ESTATE_SNAPSHOT` | Redirects/erases the occupancy source (e.g. `/dev/null` = occupancy always unknown) |
| `ADM_STATE_DIR` | Redirects the entire state dir, hiding the HALT kill switch and DRAIN flag |
| `NL_PROTECTED_ORCHESTRATOR` | Tags a dispatcher's traffic `protected=1`, excluding it from the calibration "pathology" bucket |

## Decision

**Three bypasses are CLOSED.** `ADM_ABSURD_SESSION_CAP`, `ADM_ESTATE_SNAPSHOT`, and
`ADM_STATE_DIR` are now honored only when `HARNESS_SELFTEST=1` is also set (the same
flag this lib's own self-test already used for its sandbox-diversion guard, and now
exports globally at `_adm_self_test`'s top). Grepping `adapters/claude-code` at
closure time found **zero** non-lib, non-self-test callsites setting any of the
three — no production dispatcher (workstreams-emit.sh, session-resumer.sh,
spawn-worktree.sh) has ever relied on overriding them — so this closes the bypass
for every real caller with **zero production behavior change**, while every
self-test scenario that needs the override (fixture swapping, sandbox isolation,
the bypass-pinning scenario itself) continues to work because the self-test process
now declares `HARNESS_SELFTEST=1` for its own duration. Self-test Scenario 10b
proves both halves directly against the resolver functions (`_adm_session_cap`,
`adm_state_dir`, `_adm_snapshot_path`) without ever driving a full `adm_admit` call
under `HARNESS_SELFTEST=0` — that would fall through to the *real* production state
dir and write a genuine ledger line, which is precisely the sandbox escape
Scenario 16 exists to catch.

**One bypass is ACCEPTED, staying open.** `NL_PROTECTED_ORCHESTRATOR` is not a test
convenience — it is the actual production mechanism by which the real protected
downstream-product orchestrator (docs/reviews/2026-07-27-accountable-estate-architecture-review.md
F1) tags its own dispatch traffic so calibration does not learn "normal" from a
chronic-storm baseline (design 6b edge 3). Gating it behind `HARNESS_SELFTEST` would
break its entire purpose: the real orchestrator's environment is never a self-test
context. Closing it properly would require verifying the caller's *identity*, not
just reading its *declaration* — e.g., a signed token, a process-ancestry check
against a known PID/session registry, or a capability handed out by a trusted
launcher. All three are real authentication infrastructure, disproportionate to a
0.5-bs T6 prerequisite slice, and none exist anywhere else in this harness today to
build on.

## Why this call is defensible now, not deferred

- The three closed bypasses had a mechanical, unambiguous fix (gate behind an
  existing, already-adopted sandbox flag) with a verifiable zero-callsite blast
  radius — this is exactly the "decide-and-go" class of reversible technical
  decision, not an operator judgment call.
- The fourth is a genuine architectural gap (no caller-identity verification
  anywhere in this harness), not a five-minute fix. Pretending to close it with a
  fake check (e.g. requiring a magic value that any process could still set) would
  be worse than leaving it honestly open, since it would create false confidence
  that T6's criterion (b) is fully satisfied.

## Residual risk (named, not hidden)

Any process that sources admission-lib.sh (or sets the var before invoking a
dispatcher that does) can still self-declare `NL_PROTECTED_ORCHESTRATOR=1` and
exclude its traffic from calibration. Concretely:
- **Under-count risk:** a careless or malicious process tags itself protected and
  its load never counts toward T6's pressure thresholds — thresholds could be set
  too permissive if a large share of real load hides this way.
- **Over-count risk (the opposite, also real):** the REAL protected orchestrator
  fails to set the tag (misconfiguration, new deployment, restart without the env
  var) and its legitimate 15-21/min load gets counted as "pathology," biasing
  thresholds too strict — the exact F1 failure mode this whole tagging mechanism
  exists to prevent, just from the other direction.
- Both directions are visible in the ledger (`protected:0/1` on every line, per
  Scenario 11) — an operator reviewing the 7-day calibration window before T6's
  sign-off can spot an implausible protected/unprotected split and investigate,
  which is the honest mitigation available today: **visibility, not prevention.**

## Retirement condition

Revisit this decision if: (a) the harness gains a caller-identity-verification
primitive for ANY other purpose (reuse it here rather than building a
single-purpose one), or (b) the 7-day calibration ledger shows an implausible
protected-traffic ratio (evidence the self-declaration channel is being
misused), or (c) T6 itself proposes enforcement thresholds sensitive enough that
this residual risk becomes material rather than cosmetic.

## Evidence

- Self-test: `bash adapters/claude-code/hooks/lib/admission-lib.sh --self-test`
  — Scenario 10b (closure proof), Scenario 11 (acceptance proof, unchanged),
  Scenario 17 (HARNESS_SELFTEST sandbox guard, unchanged) — 51/51 PASS.
- Grep evidence (zero production callsites for the three closed vars): `grep -rn
  "ADM_ABSURD_SESSION_CAP\|ADM_ESTATE_SNAPSHOT\|ADM_STATE_DIR" adapters/claude-code`
  returns matches only in `admission-lib.sh` itself and `manifest.json`'s
  declarative entry.
